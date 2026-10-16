import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../../shared_widgets/async_state_view.dart';
import '../../shared_widgets/date_field.dart';
import '../activity/activity_view.dart';
import '../auth/auth_controller.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';
import '../tasks/task_widgets.dart';
import 'milestone_rules.dart';
import 'milestones_tab.dart';

/// Milestone detail and edit (S11 drill-down). Saves locally; sync uploads later.
class MilestonePage extends ConsumerWidget {
  const MilestonePage({required this.milestoneId, super.key});
  final String milestoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(recordProvider(milestoneId));
    return m.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (_, _) => const Scaffold(
        body: EmptyStateView(
          title: 'Cannot load milestone',
          message: 'Restart the app. Your data is safe.',
        ),
      ),
      data: (rec) => rec == null
          ? Scaffold(
              appBar: AppBar(),
              body: const EmptyStateView(
                title: 'Milestone not found',
                message: 'It may have been deleted on another device.',
              ),
            )
          : _MilestoneEditor(key: ValueKey(rec.id), m: rec),
    );
  }
}

class _MilestoneEditor extends ConsumerStatefulWidget {
  const _MilestoneEditor({required this.m, super.key});
  final Rec m;
  @override
  ConsumerState<_MilestoneEditor> createState() => _MilestoneEditorState();
}

class _MilestoneEditorState extends ConsumerState<_MilestoneEditor> {
  late final _title = TextEditingController(text: widget.m.str('title'));
  late final _description = TextEditingController(
    text: widget.m.str('description'),
  );
  late final _weight = TextEditingController(
    text: widget.m.n('weight')?.toString() ?? '',
  );
  late String _status = widget.m.str('status', 'not_started');
  late DateTime? _due = widget.m.dt('due_at')?.toLocal();
  late String _mode = widget.m.str('progress_mode', 'manual');
  late double _value = (widget.m.n('progress_value') ?? 0).toDouble();
  late String? _parent = widget.m.s('parent_id');
  late Set<String> _deps = widget.m.list('depends_on').toSet();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _weight.dispose();
    super.dispose();
  }

  Map<String, Object?> _changes() {
    final m = widget.m;
    final desc = _description.text.trim();
    final weight = double.tryParse(_weight.text.trim());
    final due = _due == null
        ? null
        : DateTime(_due!.year, _due!.month, _due!.day, 23, 59).toUtc();
    return {
      if (_title.text.trim() != m.str('title')) 'title': _title.text.trim(),
      if ((desc.isEmpty ? null : desc) != m.s('description'))
        'description': desc.isEmpty ? null : desc,
      if (_status != m.s('status')) 'status': _status,
      if (due?.toIso8601String() != m.dt('due_at')?.toUtc().toIso8601String())
        'due_at': due,
      if (_mode != m.s('progress_mode')) 'progress_mode': _mode,
      if (_mode == 'manual' &&
          _value.round() != (m.n('progress_value') ?? 0).round())
        'progress_value': _value.round(),
      if (weight != m.n('weight')?.toDouble()) 'weight': weight,
      if (_parent != m.s('parent_id')) 'parent_id': _parent,
      if (!_sameSet(_deps, m.list('depends_on').toSet()))
        'depends_on': _deps.toList()..sort(),
    };
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> _save(List<Rec> all) async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    final w = _weight.text.trim();
    if (w.isNotEmpty && (double.tryParse(w) ?? 0) <= 0) {
      setState(() => _error = 'Weight must be a number above 0.');
      return;
    }
    final byId = {for (final x in all) x.id: x};
    final id = widget.m.id;
    if ((_parent != null &&
            wouldCycle(id, [_parent!], (x) => [?byId[x]?.s('parent_id')])) ||
        wouldCycle(id, _deps, (x) => byId[x]?.list('depends_on') ?? const [])) {
      setState(
        () => _error = 'That link would make a milestone depend on itself.',
      );
      return;
    }
    final changes = _changes();
    if (changes.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    await ref.read(recordsRepositoryProvider).change(id, changes);
    ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) {
      setState(() => _error = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved on this device')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete milestone?'),
        content: const Text(
          'Linked tasks stay, but lose this milestone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(recordsRepositoryProvider).remove(widget.m.id);
    ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(recordsProvider('milestone')).value ?? const [];
    final tasks = ref.watch(workspaceTasksProvider).value ?? const [];
    final m = widget.m;
    final siblings = [
      for (final x in projectMilestones(all, m.str('project_id')))
        if (x.id != m.id) x,
    ];
    final linked = [
      for (final t in tasks)
        if (t.milestoneId == m.id) t,
    ];
    final progress = milestoneProgress(m, all, tasks);
    final completed = m.dt('completed_at');
    final l = MaterialLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(m.str('title')),
        actions: [
          IconButton(
            tooltip: 'Delete milestone',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
          FilledButton(onPressed: () => _save(all), child: const Text('Save')),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextField(
            controller: _title,
            maxLength: 240,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _description,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              for (final s in milestoneStatuses)
                DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' '))),
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          if (completed != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Completed ${l.formatMediumDate(completed.toLocal())}',
              ),
            ),
          const SizedBox(height: 12),
          DateField(
            label: 'Due date',
            value: _due,
            onChanged: (d) => setState(() => _due = d),
          ),
          const SizedBox(height: 16),
          Text('Progress', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'manual', label: Text('Manual')),
              ButtonSegment(
                value: 'weighted',
                label: Text('Weighted (from sub-work)'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          if (_mode == 'manual')
            Slider(
              value: _value.clamp(0, 100),
              max: 100,
              divisions: 20,
              label: '${_value.round()}%',
              semanticFormatterCallback: (v) => '${v.round()} percent',
              onChanged: (v) => setState(() => _value = v),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Now ${progress.round()}%, averaged from sub-milestones by weight, '
                'or from linked tasks when there are none.',
              ),
            ),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Weight in parent (optional)',
              helperText: 'Counts more in a weighted parent. Default 1.',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _parent,
            decoration: const InputDecoration(labelText: 'Part of milestone'),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('None (top level)'),
              ),
              for (final s in siblings)
                DropdownMenuItem(value: s.id, child: Text(s.str('title'))),
            ],
            onChanged: (v) => setState(() => _parent = v),
          ),
          const SizedBox(height: 16),
          Text('Depends on', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (final s in siblings)
                FilterChip(
                  label: Text(s.str('title')),
                  selected: _deps.contains(s.id),
                  onSelected: (on) => setState(() {
                    _deps = {..._deps};
                    on ? _deps.add(s.id) : _deps.remove(s.id);
                  }),
                ),
              if (siblings.isEmpty)
                const Text('No other milestones in this project.'),
            ],
          ),
          const Divider(height: 32),
          _LinkedTasks(milestone: m, linked: linked, all: tasks),
          const Divider(height: 32),
          Semantics(
            header: true,
            container: true,
            child: Text(
              'History',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ActivityList(
            entityIds: {m.id},
            names: {for (final x in all) x.id: x.str('title')},
            shrinkWrap: true,
          ),
        ],
      ),
    );
  }
}

class _LinkedTasks extends ConsumerWidget {
  const _LinkedTasks({
    required this.milestone,
    required this.linked,
    required this.all,
  });
  final Rec milestone;
  final List<Task> linked;
  final List<Task> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(tasksRepositoryProvider);
    final projectId = milestone.str('project_id');
    Future<void> newTask() async {
      final ws = ref.read(authControllerProvider).value?.workspaceId;
      final title = await askTitle(context, 'New task for this milestone');
      if (ws == null || title == null) return;
      await repo.createIn(
        ws,
        title: title,
        projectId: projectId,
        milestoneId: milestone.id,
      );
      ref.read(syncControllerProvider.notifier).syncNow();
    }

    Future<void> linkExisting() async {
      final candidates = [
        for (final t in all)
          if (t.milestoneId != milestone.id &&
              (t.projectId == projectId || t.projectId == null) &&
              !{'complete', 'cancelled', 'archived'}.contains(t.status))
            t,
      ];
      final picked = await showDialog<Task>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Link a task'),
          children: [
            if (candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No open tasks to link.'),
              ),
            for (final t in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, t),
                child: Text(t.title),
              ),
          ],
        ),
      );
      if (picked == null) return;
      await repo.linkMilestone(picked.id, milestone.id, projectId: projectId);
      ref.read(syncControllerProvider.notifier).syncNow();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                container: true,
                child: Text(
                  'Tasks',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: linkExisting,
              icon: const Icon(Icons.link),
              label: const Text('Link task'),
            ),
            FilledButton.tonalIcon(
              onPressed: newTask,
              icon: const Icon(Icons.add_task),
              label: const Text('New task'),
            ),
          ],
        ),
        if (linked.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No tasks yet. Weighted progress uses linked tasks.'),
          ),
        for (final t in linked)
          TaskTile(
            task: t,
            trailing: IconButton(
              tooltip: 'Unlink ${t.title}',
              icon: const Icon(Icons.link_off),
              onPressed: () async {
                await repo.linkMilestone(t.id, null);
                ref.read(syncControllerProvider.notifier).syncNow();
              },
            ),
          ),
      ],
    );
  }
}
