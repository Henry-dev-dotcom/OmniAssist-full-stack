import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../../shared_widgets/async_state_view.dart';
import '../activity/activity_view.dart';
import '../analyses/analyses_tab.dart';
import '../auth/auth_controller.dart';
import '../experiments/experiments_tab.dart';
import '../milestones/milestone_rules.dart';
import '../milestones/milestones_tab.dart';
import '../records/records_repository.dart';
import '../reviews/reviews_tab.dart';
import '../sync/sync_controller.dart';
import '../tasks/task_widgets.dart';

final _projectProvider = StreamProvider.autoDispose.family<Project?, String>(
  (ref, id) => ref.watch(projectsRepositoryProvider).watchOne(id),
);

const projectStatuses = [
  'planned',
  'in_progress',
  'on_hold',
  'complete',
  'archived',
];

/// S10: progress and linked work for one project.
class ProjectPage extends ConsumerWidget {
  const ProjectPage({required this.projectId, this.initialTab = 0, super.key});
  final String projectId;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(_projectProvider(projectId));
    return project.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (_, _) => const Scaffold(
        body: EmptyStateView(
          title: 'Cannot load project',
          message: 'Restart the app. Your data is safe.',
        ),
      ),
      data: (p) => p == null || p.deletedAt != null
          ? Scaffold(
              appBar: AppBar(),
              body: const EmptyStateView(
                title: 'Project not found',
                message: 'It may have been deleted on another device.',
              ),
            )
          : DefaultTabController(
              length: 6,
              initialIndex: initialTab.clamp(0, 5),
              child: Scaffold(
                appBar: AppBar(
                  title: Text(p.name),
                  actions: [_ProjectMenu(project: p)],
                  bottom: const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'Overview'),
                      Tab(text: 'Milestones'),
                      Tab(text: 'Reviews'),
                      Tab(text: 'Analyses'),
                      Tab(text: 'Experiments'),
                      Tab(text: 'Activity'),
                    ],
                  ),
                ),
                floatingActionButton: const QuickCaptureButton(),
                body: TabBarView(
                  children: [
                    _Overview(project: p),
                    MilestonesTab(projectId: p.id),
                    ReviewsTab(projectId: p.id),
                    AnalysesTab(projectId: p.id),
                    ExperimentsTab(projectId: p.id),
                    _ProjectActivity(project: p),
                  ],
                ),
              ),
            ),
    );
  }
}

enum _MenuAction { edit, archive, delete }

class _ProjectMenu extends ConsumerWidget {
  const _ProjectMenu({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(projectsRepositoryProvider);
    final archived = project.status == 'archived';
    return PopupMenuButton<_MenuAction>(
      tooltip: 'Project actions',
      onSelected: (a) async {
        switch (a) {
          case _MenuAction.edit:
            final changes = await showDialog<Map<String, Object?>>(
              context: context,
              builder: (_) => _EditProjectDialog(project),
            );
            if (changes == null || changes.isEmpty) return;
            await repo.update(project.id, changes);
          case _MenuAction.archive:
            await repo.setArchived(project.id, !archived);
          case _MenuAction.delete:
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text('Delete ${project.name}?'),
                content: const Text(
                  'Only an empty project can be deleted. '
                  'This cannot be undone.',
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
            final why = await repo.delete(project.id);
            if (!context.mounted) return;
            if (why != null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(why)));
              return;
            }
            context.go('/app/projects');
        }
        ref.read(syncControllerProvider.notifier).syncNow();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _MenuAction.edit,
          child: Text('Edit details'),
        ),
        PopupMenuItem(
          value: _MenuAction.archive,
          child: Text(archived ? 'Restore' : 'Archive'),
        ),
        const PopupMenuItem(value: _MenuAction.delete, child: Text('Delete')),
      ],
    );
  }
}

class _EditProjectDialog extends StatefulWidget {
  const _EditProjectDialog(this.project);
  final Project project;
  @override
  State<_EditProjectDialog> createState() => _EditProjectDialogState();
}

class _EditProjectDialogState extends State<_EditProjectDialog> {
  late final _name = TextEditingController(text: widget.project.name);
  late final _description = TextEditingController(
    text: widget.project.description ?? '',
  );
  late String _status = widget.project.status;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final p = widget.project;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    final desc = _description.text.trim();
    Navigator.pop(context, <String, Object?>{
      if (name != p.name) 'name': name,
      if ((desc.isEmpty ? null : desc) != p.description)
        'description': desc.isEmpty ? null : desc,
      if (_status != p.status) 'status': _status,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit project'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            maxLength: 120,
            decoration: InputDecoration(labelText: 'Name', errorText: _error),
          ),
          TextField(
            controller: _description,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: projectStatuses.contains(_status)
                ? _status
                : 'planned',
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              for (final s in projectStatuses)
                DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' '))),
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(workspaceTasksProvider).value ?? const [];
    final milestones =
        ref.watch(recordsProvider('milestone')).value ?? const [];
    final reviews = ref.watch(recordsProvider('review')).value ?? const [];
    final analyses =
        ref.watch(recordsProvider('analysis_record')).value ?? const [];
    final experiments =
        ref.watch(recordsProvider('experiment_entry')).value ?? const [];
    bool mine(Rec r) => r.s('project_id') == project.id;
    final ms = projectMilestones(milestones, project.id)
        .where((m) => m.s('status') != 'archived' && m.s('parent_id') == null)
        .toList();
    final progress = ms.isEmpty
        ? project.progressValue.toDouble()
        : ms
                  .map((m) => milestoneProgress(m, milestones, tasks))
                  .reduce((a, b) => a + b) /
              ms.length;
    final open = [
      for (final t in tasks)
        if (t.projectId == project.id &&
            !{'complete', 'cancelled', 'archived'}.contains(t.status))
          t,
    ];
    final failed = analyses
        .where((a) => mine(a) && a.s('status') == 'failed')
        .length;

    Future<void> addTask() async {
      final ws = ref.read(authControllerProvider).value?.workspaceId;
      final title = await askTitle(context, 'New task in ${project.name}');
      if (ws == null || title == null) return;
      await ref
          .read(tasksRepositoryProvider)
          .createIn(ws, title: title, projectId: project.id);
      ref.read(syncControllerProvider.notifier).syncNow();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      children: [
        Text(
          [
            project.category,
            project.status.replaceAll('_', ' '),
            if (project.syncState != 'synced') 'waiting to sync',
          ].join(' · '),
        ),
        if (project.description case final d? when d.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(d)),
        const SizedBox(height: 16),
        Text(
          ms.isEmpty
              ? 'Progress ${progress.round()}%'
              : 'Progress ${progress.round()}% (from ${ms.length} milestones)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress / 100,
          semanticsLabel: 'Project progress',
          semanticsValue: '${progress.round()} percent',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CountChip('${milestones.where(mine).length} milestones', 1),
            _CountChip('${reviews.where(mine).length} reviews', 2),
            _CountChip(
              '${analyses.where(mine).length} analyses'
              '${failed > 0 ? ' ($failed failed)' : ''}',
              3,
            ),
            _CountChip('${experiments.where(mine).length} experiments', 4),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                container: true,
                child: Text(
                  'Open tasks',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: addTask,
              icon: const Icon(Icons.add_task),
              label: const Text('New task'),
            ),
          ],
        ),
        if (open.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No open tasks in this project.'),
          ),
        for (final t in open) TaskTile(task: t),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip(this.label, this.tab);
  final String label;
  final int tab;

  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(label),
    onPressed: () => DefaultTabController.of(context).animateTo(tab),
  );
}

class _ProjectActivity extends ConsumerWidget {
  const _ProjectActivity({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(workspaceTasksProvider).value ?? const [];
    final names = <String, String>{project.id: project.name};
    final ids = <String>{project.id};
    final reviews = <String>{};
    for (final type in const [
      'milestone',
      'review',
      'analysis_record',
      'experiment_entry',
    ]) {
      for (final r in ref.watch(recordsProvider(type)).value ?? const <Rec>[]) {
        if (r.s('project_id') != project.id) continue;
        ids.add(r.id);
        names[r.id] = r.s('title') ?? r.str('name');
        if (type == 'review') {
          reviews.add(r.id);
          for (final st in (r.data['stages'] as List<dynamic>? ?? const [])) {
            final m = st as Map<String, dynamic>;
            names['${m['id']}'] = '${m['name']}';
          }
        }
      }
    }
    for (final item
        in ref.watch(recordsProvider('review_item')).value ?? const <Rec>[]) {
      if (reviews.contains(item.s('review_id'))) {
        ids.add(item.id);
        names[item.id] = item.str('title');
      }
    }
    for (final t in tasks) {
      if (t.projectId == project.id) {
        ids.add(t.id);
        names[t.id] = t.title;
      }
    }
    return ActivityList(entityIds: ids, names: names);
  }
}
