import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../../database/app_database.dart';
import 'reminder_rules.dart';

const _choices = ['at_due', '15m', '1h', '1d', 'morning_of', 'morning_before'];

/// Reminder choices for one saved task. Each tap saves straight away.
class TaskRemindersSection extends ConsumerStatefulWidget {
  const TaskRemindersSection({required this.task, super.key});
  final Task task;
  @override
  ConsumerState<TaskRemindersSection> createState() => _State();
}

class _State extends ConsumerState<TaskRemindersSection> {
  final _chosen = <String>{};
  String _urgency = 'normal';
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(notificationRepositoryProvider).forTask(widget.task.id).then((rows) {
      final open = rows.where((r) => r.status == 'scheduled').toList();
      if (!mounted || open.isEmpty) return;
      setState(() {
        _chosen.addAll(open.map((r) => r.offsetSpec));
        _urgency = open.first.urgency;
      });
    });
  }

  Future<void> _save() async {
    try {
      await ref
          .read(notificationRepositoryProvider)
          .setForTask(widget.task, _chosen.toList(), urgency: _urgency);
      if (mounted) setState(() => _error = null);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    if (t.dueAt == null) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.notifications_none),
        title: Text('Reminders'),
        subtitle: Text('Save a due date first.'),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Reminders', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final c in _choices)
          FilterChip(
            label: Text(offsetLabel(c)),
            selected: _chosen.contains(c),
            onSelected: (on) {
              setState(() => on ? _chosen.add(c) : _chosen.remove(c));
              _save();
            },
          ),
      ]),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _urgency,
        decoration: const InputDecoration(labelText: 'Urgency'),
        items: [for (final u in urgencies) DropdownMenuItem(value: u, child: Text(u))],
        onChanged: (v) {
          setState(() => _urgency = v ?? _urgency);
          _save();
        },
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
    ]);
  }
}
