/// Recurrence rules: the RRULE subset the server accepts (decision 0005).
///   FREQ=DAILY|WEEKLY|MONTHLY|YEARLY [;INTERVAL=1..365] [;BYDAY=MO,...  (WEEKLY only)]
library;

const _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class Recurrence {
  const Recurrence(this.freq, {this.interval = 1, this.days = const {}});
  final String freq; // DAILY, WEEKLY, MONTHLY, YEARLY
  final int interval;
  final Set<int> days; // DateTime.weekday values (1 = Monday), WEEKLY only

  String toRule() => [
    'FREQ=$freq',
    if (interval != 1) 'INTERVAL=$interval',
    if (freq == 'WEEKLY' && days.isNotEmpty)
      'BYDAY=${(days.toList()..sort()).map((d) => _days[d - 1]).join(',')}',
  ].join(';');

  String describe() {
    final unit = const {
      'DAILY': 'day',
      'WEEKLY': 'week',
      'MONTHLY': 'month',
      'YEARLY': 'year',
    }[freq]!;
    final every = interval == 1 ? 'Every $unit' : 'Every $interval ${unit}s';
    if (freq == 'WEEKLY' && days.isNotEmpty) {
      return '$every on ${(days.toList()..sort()).map((d) => dayNames[d - 1]).join(', ')}';
    }
    return every;
  }
}

/// Parses [rule], or throws [FormatException] with a message for the form field.
/// The messages match the server's, so local and server checks agree.
Recurrence parseRule(String rule) {
  final parts = <String, String>{};
  for (final item in rule.trim().split(';')) {
    final i = item.indexOf('=');
    if (i <= 0 || i == item.length - 1) {
      throw const FormatException(
        "Use KEY=VALUE pairs separated by ';', e.g. FREQ=WEEKLY;BYDAY=MO",
      );
    }
    final key = item.substring(0, i);
    if (parts.containsKey(key)) throw FormatException('$key appears twice');
    parts[key] = item.substring(i + 1);
  }
  final unknown = parts.keys.toSet().difference({'FREQ', 'INTERVAL', 'BYDAY'});
  if (unknown.isNotEmpty) {
    throw FormatException(
      'Unsupported part: ${(unknown.toList()..sort()).join(', ')}',
    );
  }
  final freq = parts['FREQ'];
  if (!const {'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(freq)) {
    throw const FormatException(
      'FREQ must be DAILY, WEEKLY, MONTHLY or YEARLY',
    );
  }
  var interval = 1;
  if (parts['INTERVAL'] case final n?) {
    final v = int.tryParse(n);
    if (v == null || v < 1 || v > 365 || '$v' != n) {
      throw const FormatException(
        'INTERVAL must be a whole number from 1 to 365',
      );
    }
    interval = v;
  }
  var days = <int>{};
  if (parts['BYDAY'] case final list?) {
    if (freq != 'WEEKLY') {
      throw const FormatException('BYDAY works only with FREQ=WEEKLY');
    }
    final names = list.split(',');
    if (names.any((d) => !_days.contains(d)) ||
        names.toSet().length != names.length) {
      throw const FormatException('BYDAY lists days like MO,WE,FR');
    }
    days = {for (final d in names) _days.indexOf(d) + 1};
  }
  return Recurrence(freq!, interval: interval, days: days);
}

/// The first occurrence after [due], at the same local time of day.
DateTime nextOccurrence(DateTime due, Recurrence r) {
  final d = due.toLocal();
  DateTime at(int y, int m, int day) =>
      DateTime(y, m, day, d.hour, d.minute, d.second);
  switch (r.freq) {
    case 'DAILY':
      return at(d.year, d.month, d.day + r.interval);
    case 'WEEKLY':
      if (r.days.isEmpty) return at(d.year, d.month, d.day + 7 * r.interval);
      // Later this week, else the first chosen day of the next active week.
      for (var i = 1; i <= 7 - d.weekday; i++) {
        if (r.days.contains(d.weekday + i)) {
          return at(d.year, d.month, d.day + i);
        }
      }
      final monday = at(
        d.year,
        d.month,
        d.day - (d.weekday - 1) + 7 * r.interval,
      );
      final first = (r.days.toList()..sort()).first;
      return at(monday.year, monday.month, monday.day + first - 1);
    case 'MONTHLY':
      return _clamped(d.year, d.month + r.interval, d.day, d);
    default: // YEARLY
      return _clamped(d.year + r.interval, d.month, d.day, d);
  }
}

/// Day 31 in a 30-day month becomes the 30th, not the 1st of the next month.
DateTime _clamped(int y, int m, int day, DateTime time) {
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(
    y,
    m,
    day > last ? last : day,
    time.hour,
    time.minute,
    time.second,
  );
}
