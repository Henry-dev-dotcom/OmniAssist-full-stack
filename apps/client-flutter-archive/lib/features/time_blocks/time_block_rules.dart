import '../../database/app_database.dart';

/// Mirrors the server rules (apps/api/src/domain/time_blocks/service.py), so the
/// UI can explain a problem before sync does.
const blockStatuses = [
  'planned',
  'in_progress',
  'complete',
  'skipped',
  'cancelled',
];
const blockCategories = [
  'focus',
  'meeting',
  'admin',
  'break',
  'personal',
  'other',
];

const _allowed = <String, Set<String>>{
  'planned': {'in_progress', 'complete', 'skipped', 'cancelled'},
  'in_progress': {'planned', 'complete', 'skipped', 'cancelled'},
  'complete': {'planned'},
  'skipped': {'planned'},
  'cancelled': {'planned'},
};

/// Statuses a block with [current] can move to, including staying put.
List<String> nextStatuses(String current) => [current, ...?_allowed[current]];

bool canTransition(String from, String to) =>
    from == to || (_allowed[from]?.contains(to) ?? false);

/// Skipped and cancelled blocks free their time, so they never clash.
const _free = {'skipped', 'cancelled'};

/// Null when the range is fine; otherwise the reason it is not.
String? validateRange(DateTime start, DateTime end) =>
    end.isAfter(start) ? null : 'The end must be after the start.';

/// Other blocks that share time with [start, end). Touching edges do not overlap.
List<TimeBlock> overlapping(
  DateTime start,
  DateTime end,
  Iterable<TimeBlock> others, {
  String? excludeId,
}) => [
  for (final b in others)
    if (b.id != excludeId &&
        b.deletedAt == null &&
        !_free.contains(b.status) &&
        b.startsAt.isBefore(end) &&
        b.endsAt.isAfter(start))
      b,
];
