import '../../database/app_database.dart';
import '../records/records_repository.dart';

const milestoneStatuses = [
  'not_started',
  'in_progress',
  'at_risk',
  'blocked',
  'complete',
  'archived',
];

bool isMilestoneOpen(Rec m) =>
    !{'complete', 'archived'}.contains(m.s('status'));

/// Past due and not finished. Flagged only; the status never changes by itself (Spec 4.7).
bool isMilestoneOverdue(Rec m, DateTime now) {
  final due = m.dt('due_at');
  return due != null && due.isBefore(now) && isMilestoneOpen(m);
}

/// Shown under "At risk": overdue, due within [soon] while not started, or marked so.
bool isMilestoneAtRisk(
  Rec m,
  DateTime now, {
  Duration soon = const Duration(days: 7),
}) {
  if (!isMilestoneOpen(m)) return false;
  if ({'at_risk', 'blocked'}.contains(m.s('status'))) return true;
  final due = m.dt('due_at');
  if (due == null) return false;
  return due.isBefore(now) ||
      (m.s('status') == 'not_started' && due.isBefore(now.add(soon)));
}

/// Blocked by a dependency that is not complete yet.
bool isMilestoneBlocked(Rec m, Map<String, Rec> byId) => m
    .list('depends_on')
    .any((d) => byId[d] != null && byId[d]!.s('status') != 'complete');

/// Progress 0..100 (decision 0003). Manual: the stored value. Weighted: weighted average
/// of child milestones (weight defaults to 1), else the share of linked tasks complete.
double milestoneProgress(Rec m, List<Rec> all, List<Task> tasks) {
  if (m.s('status') == 'complete') return 100;
  if (m.s('progress_mode') != 'weighted') {
    return (m.n('progress_value') ?? 0).toDouble().clamp(0, 100);
  }
  final children = [
    for (final c in all)
      if (c.s('parent_id') == m.id && c.s('status') != 'archived') c,
  ];
  if (children.isNotEmpty) {
    var total = 0.0, sum = 0.0;
    for (final c in children) {
      final w = (c.n('weight') ?? 1).toDouble();
      total += w;
      sum += w * milestoneProgress(c, all, tasks);
    }
    return total == 0 ? 0 : (sum / total).clamp(0, 100);
  }
  final linked = [
    for (final t in tasks)
      if (t.milestoneId == m.id &&
          t.deletedAt == null &&
          t.status != 'cancelled')
        t,
  ];
  if (linked.isEmpty) return 0;
  return 100 *
      linked.where((t) => t.status == 'complete').length /
      linked.length;
}

/// True if pointing [id] at [targets] (as parent or as dependencies) would make a loop,
/// following [next] (each id to the ids it already points at). The server checks too.
bool wouldCycle(
  String id,
  Iterable<String> targets,
  List<String> Function(String) next,
) {
  final seen = <String>{};
  final stack = [...targets];
  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    if (cur == id) return true;
    if (seen.add(cur)) stack.addAll(next(cur));
  }
  return false;
}
