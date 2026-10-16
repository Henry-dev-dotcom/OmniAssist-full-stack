import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../sync/sync_controller.dart';
import 'recurrence.dart';
import 'task_widgets.dart';

const _presets = <String, Recurrence?>{
  'none': null,
  'daily': Recurrence('DAILY'),
  'weekdays': Recurrence('WEEKLY', days: {1, 2, 3, 4, 5}),
  'weekly': Recurrence('WEEKLY'),
  'monthly': Recurrence('MONTHLY'),
  'yearly': Recurrence('YEARLY'),
};

const _units = {
  'DAILY': 'day(s)',
  'WEEKLY': 'week(s)',
  'MONTHLY': 'month(s)',
  'YEARLY': 'year(s)',
};

/// Repeat options as plain choices; the rule text stays hidden (decision 0005).
class RepeatPicker extends StatelessWidget {
  const RepeatPicker({required this.value, required this.onChanged, super.key});
  final Recurrence? value;
  final ValueChanged<Recurrence?> onChanged;

  String get _kind {
    final v = value;
    if (v == null) return 'none';
    final weekdays =
        v.freq == 'WEEKLY' &&
        v.interval == 1 &&
        v.days.length == 5 &&
        v.days.every((d) => d <= 5);
    return weekdays ? 'weekdays' : v.freq.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final v = value;
    const steps = [1, 2, 3, 4, 6, 12];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Repeat'),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Does not repeat')),
            DropdownMenuItem(value: 'daily', child: Text('Daily')),
            DropdownMenuItem(value: 'weekdays', child: Text('Every weekday')),
            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
            DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
          ],
          onChanged: (k) => onChanged(_presets[k]),
        ),
        if (v != null && _kind != 'weekdays') ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Every '),
              DropdownButton<int>(
                value: v.interval,
                items: [
                  for (final n in steps)
                    DropdownMenuItem(value: n, child: Text('$n')),
                  if (!steps.contains(v.interval))
                    DropdownMenuItem(
                      value: v.interval,
                      child: Text('${v.interval}'),
                    ),
                ],
                onChanged: (n) => onChanged(
                  Recurrence(v.freq, interval: n ?? 1, days: v.days),
                ),
              ),
              Text(' ${_units[v.freq]}'),
            ],
          ),
          if (v.freq == 'WEEKLY')
            Wrap(
              spacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(dayNames[d - 1]),
                    selected: v.days.contains(d),
                    onSelected: (on) => onChanged(
                      Recurrence(
                        'WEEKLY',
                        interval: v.interval,
                        days: on ? {...v.days, d} : ({...v.days}..remove(d)),
                      ),
                    ),
                  ),
              ],
            ),
        ],
        if (v != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${v.describe()}. Completing it creates the next one.'),
          ),
      ],
    );
  }
}

final _subtasksProvider = StreamProvider.autoDispose.family<List<Task>, Task>(
  (ref, parent) => ref.watch(tasksRepositoryProvider).watchSubtasks(parent),
);

class SubtaskList extends ConsumerWidget {
  const SubtaskList({
    required this.parent,
    required this.controller,
    super.key,
  });
  final Task parent;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtasks = ref.watch(_subtasksProvider(parent)).value ?? const [];
    final done = subtasks.where((t) => t.status == 'complete').length;
    Future<void> add() async {
      if (controller.text.trim().isEmpty) return;
      await ref
          .read(tasksRepositoryProvider)
          .addSubtask(parent, controller.text);
      controller.clear();
      ref.read(syncControllerProvider.notifier).syncNow();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          container: true,
          child: Text(
            subtasks.isEmpty
                ? 'Subtasks'
                : 'Subtasks ($done of ${subtasks.length} done)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final t in subtasks) TaskTile(task: t),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLength: 240,
                onSubmitted: (_) => add(),
                decoration: const InputDecoration(labelText: 'Add a subtask'),
              ),
            ),
            IconButton(
              tooltip: 'Add subtask',
              onPressed: add,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
