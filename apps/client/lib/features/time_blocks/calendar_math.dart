import '../../database/app_database.dart';

/// Local-time calendar helpers. Pure functions so they are easy to test.
DateTime dayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

DateTime addDays(DateTime day, int n) =>
    DateTime(day.year, day.month, day.day + n);

/// Monday of the week that holds [day].
DateTime weekStart(DateTime day) =>
    addDays(dayOf(day), -(dayOf(day).weekday - 1));

DateTime monthStart(DateTime day) => DateTime(day.year, day.month);

/// Cells for a month grid: whole weeks, Monday first (4 to 6 rows of 7).
List<DateTime> monthCells(DateTime day) {
  final first = monthStart(day);
  final last = DateTime(day.year, day.month + 1, 0);
  final start = weekStart(first);
  final end = addDays(weekStart(last), 7);
  return [for (var d = start; d.isBefore(end); d = addDays(d, 1)) d];
}

/// Blocks that touch the local day [day], in start order.
List<TimeBlock> blocksOnDay(Iterable<TimeBlock> all, DateTime day) {
  final s = dayOf(day);
  final e = addDays(s, 1);
  return all
      .where(
        (b) =>
            b.startsAt.toLocal().isBefore(e) && b.endsAt.toLocal().isAfter(s),
      )
      .toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
}

String hhmm(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String blockRange(TimeBlock b) => '${hhmm(b.startsAt)} – ${hhmm(b.endsAt)}';

/// First free slot of [length] on [day] from [from] (local), skipping busy blocks.
DateTime nextFreeStart(
  Iterable<TimeBlock> dayBlocks,
  DateTime from,
  Duration length,
) {
  var at = from;
  final busy =
      dayBlocks
          .where((b) => b.status != 'skipped' && b.status != 'cancelled')
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  for (final b in busy) {
    final bs = b.startsAt.toLocal(), be = b.endsAt.toLocal();
    if (!at.add(length).isAfter(bs)) break;
    if (be.isAfter(at)) at = be;
  }
  return at;
}
