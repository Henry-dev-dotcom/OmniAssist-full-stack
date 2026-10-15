import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../auth/auth_controller.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';
import 'milestone_rules.dart';

final workspaceTasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  return ws == null
      ? const Stream.empty()
      : ref.watch(databaseProvider).taskDao.watchActive(ws);
});

/// Milestones of one project, in timeline order (due date, undated last).
List<Rec> projectMilestones(List<Rec> all, String projectId) {
  final far = DateTime.utc(9999);
  return [
    for (final m in all)
      if (m.s('project_id') == projectId) m,
  ]..sort((a, b) => (a.dt('due_at') ?? far).compareTo(b.dt('due_at') ?? far));
}

/// S11: timeline, progress, upcoming, at risk and blocked.
class MilestonesTab extends ConsumerWidget {
  const MilestonesTab({required this.projectId, super.key});
  final String projectId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    if (ws == null) return;
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _TitleDialog(title: 'New milestone'),
    );
    if (title == null) return;
    final id = await ref.read(recordsRepositoryProvider).create(
      ws,
      'milestone',
      {
        'project_id': projectId,
        'title': title,
        'status': 'not_started',
        'progress_mode': 'manual',
        'progress_value': 0,
        'depends_on': <String>[],
      },
    );
    ref.read(syncControllerProvider.notifier).syncNow();
    if (context.mounted) await context.push('/app/milestones/$id');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(recordsProvider('milestone')).value ?? const [];
    final tasks = ref.watch(workspaceTasksProvider).value ?? const [];
    final now = ref.watch(clockProvider).now();
    final ms = projectMilestones(all, projectId);
    final byId = {for (final m in all) m.id: m};
    final live = ms.where((m) => m.s('status') != 'archived').toList();
    final top = live.where((m) => m.s('parent_id') == null).toList();
    final overall = top.isEmpty
        ? 0.0
        : top
                  .map((m) => milestoneProgress(m, all, tasks))
                  .reduce((a, b) => a + b) /
              top.length;
    final atRisk = live.where((m) => isMilestoneAtRisk(m, now)).length;
    final blocked = live.where((m) => isMilestoneBlocked(m, byId)).length;
    final upcoming = live
        .where(
          (m) =>
              isMilestoneOpen(m) &&
              m.dt('due_at') != null &&
              !m.dt('due_at')!.isBefore(now) &&
              m.dt('due_at')!.isBefore(now.add(const Duration(days: 30))),
        )
        .length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Stat('Progress', '${overall.round()}%', Icons.donut_large),
              _Stat(
                'At risk',
                '$atRisk',
                Icons.warning_amber_outlined,
                attention: atRisk > 0,
              ),
              _Stat('Blocked', '$blocked', Icons.block, attention: blocked > 0),
              _Stat('Due in 30 days', '$upcoming', Icons.event_outlined),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  container: true,
                  child: Text(
                    'Timeline',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Milestone'),
              ),
            ],
          ),
        ),
        if (ms.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No milestones yet. Break the project into outcomes such as '
              '"Draft Chapter 2" and link tasks to them.',
            ),
          ),
        for (final m in ms)
          MilestoneTile(
            m: m,
            progress: milestoneProgress(m, all, tasks),
            now: now,
            blockedBy: [
              for (final d in m.list('depends_on'))
                if (byId[d] != null && byId[d]!.s('status') != 'complete')
                  byId[d]!.str('title'),
            ],
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, {this.attention = false});
  final String label;
  final String value;
  final IconData icon;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final color = attention ? Theme.of(context).colorScheme.error : null;
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: color),
                  ),
                  Text(label),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One timeline row: status, due date, progress (manual and weighted look different).
class MilestoneTile extends StatelessWidget {
  const MilestoneTile({
    required this.m,
    required this.progress,
    required this.now,
    this.blockedBy = const [],
    super.key,
  });
  final Rec m;
  final double progress;
  final DateTime now;
  final List<String> blockedBy;

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    final due = m.dt('due_at');
    final weighted = m.s('progress_mode') == 'weighted';
    final error = Theme.of(context).colorScheme.error;
    final flags = [
      if (isMilestoneOverdue(m, now)) 'Overdue',
      if (!isMilestoneOverdue(m, now) && isMilestoneAtRisk(m, now)) 'At risk',
      if (blockedBy.isNotEmpty) 'Blocked by ${blockedBy.join(', ')}',
      if (m.pending) 'Waiting to sync',
    ];
    return ListTile(
      leading: Icon(switch (m.s('status')) {
        'complete' => Icons.check_circle,
        'blocked' => Icons.block,
        'at_risk' => Icons.warning_amber_outlined,
        'in_progress' => Icons.timelapse,
        'archived' => Icons.archive_outlined,
        _ => Icons.radio_button_unchecked,
      }, color: flags.any((f) => f != 'Waiting to sync') ? error : null),
      title: Text(
        m.str('title'),
        style: m.s('parent_id') == null
            ? null
            : Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              m.str('status').replaceAll('_', ' '),
              if (due != null) 'due ${l.formatMediumDate(due.toLocal())}',
              if (m.s('parent_id') != null) 'sub-milestone',
              ...flags,
            ].join(' · '),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: progress / 100,
                  semanticsLabel: '${m.str('title')} progress',
                  semanticsValue: '${progress.round()} percent',
                ),
              ),
              const SizedBox(width: 8),
              // Weighted progress is computed, so it is labelled and drawn differently.
              Text(
                weighted
                    ? 'Weighted ${progress.round()}% (auto)'
                    : 'Manual ${progress.round()}%',
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      onTap: () => context.push('/app/milestones/${m.id}'),
    );
  }
}

class _TitleDialog extends StatefulWidget {
  const _TitleDialog({required this.title});
  final String title;
  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    if (_c.text.trim().isEmpty) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    Navigator.pop(context, _c.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      maxLength: 240,
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(labelText: 'Title', errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Create')),
    ],
  );
}

/// Shared single-field prompt; returns the trimmed text or null.
Future<String?> askTitle(BuildContext context, String title) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TitleDialog(title: title),
    );
