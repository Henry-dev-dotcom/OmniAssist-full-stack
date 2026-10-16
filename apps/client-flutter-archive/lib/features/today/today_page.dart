import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../../shared_widgets/async_state_view.dart';
import '../auth/auth_controller.dart';
import '../milestones/milestone_rules.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_status.dart';
import '../tasks/task_widgets.dart';
import '../tasks/tasks_repository.dart';
import 'today_briefing.dart';

final _tasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  return ws == null
      ? const Stream.empty()
      : ref.watch(databaseProvider).taskDao.watchActive(ws);
});

final _blocksProvider = StreamProvider.autoDispose<List<TimeBlock>>((ref) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  if (ws == null) return const Stream.empty();
  final n = ref.watch(clockProvider).now().toLocal();
  final start = DateTime(n.year, n.month, n.day);
  return ref
      .watch(timeBlocksRepositoryProvider)
      .watchRange(
        ws,
        start.toUtc(),
        start.add(const Duration(days: 1)).toUtc(),
      );
});

/// The daily briefing (S05). Loads only local data, so it works offline.
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(_tasksProvider);
    final blocks = ref.watch(_blocksProvider);
    final milestones = ref.watch(recordsProvider('milestone'));
    final now = ref.watch(clockProvider).now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/app/notifications'),
            icon: const Icon(Icons.notifications_outlined),
          ),
          const SyncStatusChip(),
        ],
      ),
      floatingActionButton: const QuickCaptureButton(),
      body: switch ((tasks, blocks, milestones)) {
        (AsyncError(), _, _) ||
        (_, AsyncError(), _) ||
        (_, _, AsyncError()) => const EmptyStateView(
          title: 'Cannot load Today',
          message: 'Restart the app. Your data is safe.',
        ),
        (
          AsyncData(value: final t),
          AsyncData(value: final b),
          AsyncData(value: final m),
        ) =>
          _Briefing(
            buildBriefing(tasks: t, blocks: b, milestones: m, now: now),
            now,
          ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Briefing extends ConsumerWidget {
  const _Briefing(this.b, this.now);
  final TodayBriefing b;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heading = MaterialLocalizations.of(context)
        .formatFullDate(now.toLocal());
    if (b.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(heading, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            container: true,
            child: Text(
              'A clear day',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nothing is due, scheduled or at risk. Start by adding something.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => captureTask(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Capture a task'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/app/calendar'),
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Plan a time block'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/app/projects'),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Start a project'),
              ),
            ],
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(heading, style: Theme.of(context).textTheme.titleMedium),
        ),
        _Section('Top priorities', [
          for (final t in b.priorities) _TaskRow(t),
        ], empty: 'No urgent work. Pick something from your projects.'),
        if (b.blocks.isNotEmpty)
          _Section('Scheduled', [for (final x in b.blocks) _BlockRow(x)]),
        if (b.overdue.isNotEmpty)
          _Section('Overdue', [
            for (final t in b.overdue) _TaskRow(t, overdue: true),
          ]),
        if (b.dueToday.isNotEmpty)
          _Section('Also due today', [for (final t in b.dueToday) _TaskRow(t)]),
        if (b.routines.isNotEmpty)
          _Section('Routines', [for (final t in b.routines) _TaskRow(t)]),
        if (b.milestones.isNotEmpty)
          _Section('Milestones', [
            for (final m in b.milestones) _MilestoneRow(m, now),
          ]),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children, {this.empty});
  final String title;
  final List<Widget> children;
  final String? empty;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Semantics(
          header: true,
          container: true,
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
      ),
      if (children.isEmpty && empty != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(empty!),
        ),
      ...children,
    ],
  );
}

enum _TaskAction { snooze, reschedule, open }

class _TaskRow extends ConsumerWidget {
  const _TaskRow(this.task, {this.overdue = false});
  final Task task;
  final bool overdue;

  Future<void> _act(BuildContext context, WidgetRef ref, _TaskAction a) async {
    final repo = ref.read(tasksRepositoryProvider);
    final now = ref.read(clockProvider).now().toLocal();
    switch (a) {
      case _TaskAction.open:
        await context.push('/app/tasks/${task.id}');
        return;
      case _TaskAction.snooze:
        await repo.reschedule(
          task.id,
          dueFromDate(now.add(const Duration(days: 1))),
        );
      case _TaskAction.reschedule:
        final picked = await showDatePicker(
          context: context,
          initialDate: now,
          firstDate: now.subtract(const Duration(days: 365)),
          lastDate: now.add(const Duration(days: 365 * 5)),
          helpText: 'Reschedule ${task.title}',
        );
        if (picked == null) return;
        await repo.reschedule(task.id, dueFromDate(picked));
    }
    ref.read(syncControllerProvider.notifier).syncNow();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = Theme.of(context).colorScheme.error;
    return TaskTile(
      task: task,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (overdue)
            Tooltip(
              message: 'Overdue',
              child: Icon(
                Icons.schedule,
                color: error,
                semanticLabel: 'Overdue',
              ),
            ),
          if ({'high', 'critical'}.contains(task.priority))
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Chip(
                label: Text(task.priority),
                visualDensity: VisualDensity.compact,
              ),
            ),
          PopupMenuButton<_TaskAction>(
            tooltip: 'More actions for ${task.title}',
            onSelected: (a) => _act(context, ref, a),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _TaskAction.snooze,
                child: Text('Snooze to tomorrow'),
              ),
              PopupMenuItem(
                value: _TaskAction.reschedule,
                child: Text('Reschedule…'),
              ),
              PopupMenuItem(value: _TaskAction.open, child: Text('Open')),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow(this.block);
  final TimeBlock block;

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    String t(DateTime d) =>
        l.formatTimeOfDay(TimeOfDay.fromDateTime(d.toLocal()));
    return ListTile(
      leading: const Icon(Icons.event_outlined),
      title: Text(block.title),
      subtitle: Text(
        '${t(block.startsAt)} – ${t(block.endsAt)} · ${block.category}',
      ),
      onTap: () => context.go('/app/calendar'),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow(this.m, this.now);
  final Rec m;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final due = m.dt('due_at');
    final flag = isMilestoneOverdue(m, now)
        ? 'Overdue'
        : isMilestoneAtRisk(m, now)
        ? 'At risk'
        : null;
    final l = MaterialLocalizations.of(context);
    return ListTile(
      leading: Icon(
        flag == null ? Icons.flag_outlined : Icons.warning_amber_outlined,
        color: flag == null ? null : Theme.of(context).colorScheme.error,
      ),
      title: Text(m.str('title')),
      subtitle: Text(
        [
          ?flag,
          if (due != null) 'Due ${l.formatMediumDate(due.toLocal())}',
          m.str('status').replaceAll('_', ' '),
        ].join(' · '),
      ),
      onTap: () => context.push('/app/projects/${m.s('project_id')}'),
    );
  }
}
