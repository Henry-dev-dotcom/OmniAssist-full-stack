import '../../database/app_database.dart';
import '../milestones/milestone_rules.dart';
import '../records/records_repository.dart';

const _closed = {'complete', 'cancelled', 'archived'};
const _rank = {'critical': 0, 'high': 1, 'normal': 2, 'low': 3};

/// Everything Today shows, computed from local data only (Spec 4.6).
class TodayBriefing {
  const TodayBriefing({
    required this.priorities,
    required this.overdue,
    required this.dueToday,
    required this.routines,
    required this.blocks,
    required this.milestones,
  });
  final List<Task> priorities;
  final List<Task> overdue;
  final List<Task> dueToday;
  final List<Task> routines;
  final List<TimeBlock> blocks;
  final List<Rec> milestones;

  bool get isEmpty =>
      priorities.isEmpty &&
      overdue.isEmpty &&
      dueToday.isEmpty &&
      routines.isEmpty &&
      blocks.isEmpty &&
      milestones.isEmpty;
}

/// [now] is local wall time; "today" ends at local midnight.
TodayBriefing buildBriefing({
  required List<Task> tasks,
  required List<TimeBlock> blocks,
  required List<Rec> milestones,
  required DateTime now,
  int top = 3,
  Duration milestoneHorizon = const Duration(days: 14),
}) {
  final local = now.toLocal();
  final start = DateTime(local.year, local.month, local.day);
  final end = start.add(const Duration(days: 1));
  final open = [
    for (final t in tasks)
      if (t.deletedAt == null && !_closed.contains(t.status)) t,
  ];
  bool due(Task t, bool Function(DateTime) test) =>
      t.dueAt != null && test(t.dueAt!.toLocal());
  bool isRoutine(Task t) =>
      t.recurrenceRule != null &&
      (t.dueAt == null || due(t, (d) => d.isBefore(end)));

  int byUrgency(Task a, Task b) {
    final p = (_rank[a.priority] ?? 2).compareTo(_rank[b.priority] ?? 2);
    if (p != 0) return p;
    final ad = a.dueAt, bd = b.dueAt;
    if (ad == null || bd == null) return ad == null ? (bd == null ? 0 : 1) : -1;
    return ad.compareTo(bd);
  }

  final routines = [
    for (final t in open)
      if (isRoutine(t)) t,
  ];
  final candidates = [
    for (final t in open)
      if (!isRoutine(t) &&
          ({'high', 'critical'}.contains(t.priority) ||
              due(t, (d) => d.isBefore(end))))
        t,
  ]..sort(byUrgency);
  final priorities = candidates.take(top).toList();
  final shown = {
    for (final t in [...priorities, ...routines]) t.id,
  };

  final overdue = [
    for (final t in open)
      if (!shown.contains(t.id) && due(t, (d) => d.isBefore(start))) t,
  ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  final dueToday = [
    for (final t in open)
      if (!shown.contains(t.id) &&
          due(t, (d) => !d.isBefore(start) && d.isBefore(end)))
        t,
  ]..sort(byUrgency);

  final todayBlocks = [
    for (final b in blocks)
      if (b.deletedAt == null &&
          b.status != 'cancelled' &&
          b.startsAt.toLocal().isBefore(end) &&
          b.endsAt.toLocal().isAfter(start))
        b,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  final horizon = now.add(milestoneHorizon);
  final ms =
      [
        for (final m in milestones)
          if (isMilestoneOpen(m) &&
              (isMilestoneAtRisk(m, now) ||
                  (m.dt('due_at') != null &&
                      m.dt('due_at')!.isBefore(horizon))))
            m,
      ]..sort(
        (a, b) =>
            (a.dt('due_at') ?? horizon).compareTo(b.dt('due_at') ?? horizon),
      );

  return TodayBriefing(
    priorities: priorities,
    overdue: overdue,
    dueToday: dueToday,
    routines: routines,
    blocks: todayBlocks,
    milestones: ms,
  );
}
