import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../../database/app_database.dart';
import 'calendar_math.dart';
import 'time_block_rules.dart';

String overlapMessage(List<TimeBlock> clashes) => clashes.length == 1
    ? 'Saved. It overlaps "${clashes.first.title}".'
    : 'Saved. It overlaps ${clashes.length} other blocks.';

Future<void> showTimeBlockEditor(
  BuildContext context, {
  required String ws,
  required DateTime day,
  TimeBlock? block,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _Editor(ws: ws, day: day, block: block),
);

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.ws, required this.day, this.block});
  final String ws;
  final DateTime day;
  final TimeBlock? block;
  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late final _title = TextEditingController(text: widget.block?.title ?? '');
  late String _category = widget.block?.category ?? 'focus';
  late DateTime _start =
      widget.block?.startsAt.toLocal() ??
      DateTime(widget.day.year, widget.day.month, widget.day.day, 9);
  late DateTime _end =
      widget.block?.endsAt.toLocal() ?? _start.add(const Duration(hours: 1));
  late String _status = widget.block?.status ?? 'planned';
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    final repo = ref.read(timeBlocksRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final b = widget.block;
      final saved = b == null
          ? await repo.create(
              ws: widget.ws,
              title: _title.text,
              category: _category,
              startsAt: _start,
              endsAt: _end,
            )
          : await repo.edit(
              b.id,
              title: _title.text,
              category: _category,
              startsAt: _start,
              endsAt: _end,
              status: _status,
            );
      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved.overlaps.isEmpty ? 'Saved.' : overlapMessage(saved.overlaps),
          ),
        ),
      );
    } on AppError catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.block != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing ? 'Edit time block' : 'New time block',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: !editing,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in {...blockCategories, _category})
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            if (editing) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final s in nextStatuses(widget.block!.status))
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starts'),
              subtitle: Text(
                '${_start.year}-${_start.month}-${_start.day} ${hhmm(_start)}',
              ),
              onTap: () async {
                final d = await _pick(_start);
                if (d == null) return;
                setState(() {
                  final len = _end.difference(_start);
                  _start = d;
                  _end = d.add(len);
                });
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ends'),
              subtitle: Text(
                '${_end.year}-${_end.month}-${_end.day} ${hhmm(_end)}',
              ),
              onTap: () async {
                final d = await _pick(_end);
                if (d != null) setState(() => _end = d);
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Row(
              children: [
                if (editing)
                  TextButton(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      await ref
                          .read(timeBlocksRepositoryProvider)
                          .delete(widget.block!.id);
                      nav.pop();
                    },
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in a day or agenda list. Shows range, status and move buttons.
class BlockTile extends ConsumerWidget {
  const BlockTile({super.key, required this.block});
  final TimeBlock block;

  Future<void> _move(BuildContext context, WidgetRef ref, Duration by) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await ref
        .read(timeBlocksRepositoryProvider)
        .reschedule(block.id, block.startsAt.add(by), block.endsAt.add(by));
    if (r.overlaps.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(overlapMessage(r.overlaps))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = block.status == 'complete';
    final off = block.status == 'skipped' || block.status == 'cancelled';
    return ListTile(
      onTap: () => showTimeBlockEditor(
        context,
        ws: block.workspaceId,
        day: dayOf(block.startsAt),
        block: block,
      ),
      title: Text(
        block.title,
        style: TextStyle(
          decoration: (done || off) ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '${blockRange(block)} · ${block.category} · ${block.status}',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Move',
        onSelected: (v) => switch (v) {
          'earlier' => _move(context, ref, const Duration(minutes: -15)),
          'later' => _move(context, ref, const Duration(minutes: 15)),
          'yesterday' => _move(context, ref, const Duration(days: -1)),
          _ => _move(context, ref, const Duration(days: 1)),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'earlier', child: Text('15 min earlier')),
          PopupMenuItem(value: 'later', child: Text('15 min later')),
          PopupMenuItem(value: 'yesterday', child: Text('Previous day')),
          PopupMenuItem(value: 'tomorrow', child: Text('Next day')),
        ],
      ),
    );
  }
}
