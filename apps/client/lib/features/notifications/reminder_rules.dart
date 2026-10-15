/// Reminder maths. It uses the device's local time zone, which is the user's, so a
/// "9:00 morning" reminder stays at 9:00 across daylight-saving changes.
/// Mirrors apps/api/src/domain/notifications/service.py.
const reminderPresets = {'at_due': 0, '15m': 15, '1h': 60, '1d': 1440};
const _morning = {'morning_of': 0, 'morning_before': 1};
const morningHour = 9;
const maxCustomMinutes = 60 * 24 * 90;
const urgencies = ['low', 'normal', 'high', 'critical'];
const closedTaskStates = {'complete', 'cancelled', 'archived'};

bool isValidOffset(String spec) {
  if (reminderPresets.containsKey(spec) || _morning.containsKey(spec)) {
    return true;
  }
  if (!spec.startsWith('custom:')) return false;
  final m = int.tryParse(spec.substring(7));
  return m != null && m >= 0 && m <= maxCustomMinutes;
}

String offsetLabel(String spec) => switch (spec) {
  'at_due' => 'When due',
  '15m' => '15 minutes before',
  '1h' => '1 hour before',
  '1d' => '1 day before',
  'morning_of' => '9:00 on the day',
  'morning_before' => '9:00 the day before',
  _ =>
    spec.startsWith('custom:') ? '${spec.substring(7)} minutes before' : spec,
};

/// When to remind for [due] (UTC in, UTC out).
DateTime remindAt(DateTime due, String spec) {
  if (!isValidOffset(spec)) throw ArgumentError('bad reminder offset: $spec');
  if (_morning.containsKey(spec)) {
    final d = due.toLocal();
    return DateTime(
      d.year,
      d.month,
      d.day - _morning[spec]!,
      morningHour,
    ).toUtc();
  }
  final minutes = reminderPresets[spec] ?? int.parse(spec.substring(7));
  return due.toUtc().subtract(Duration(minutes: minutes));
}

class QuietHours {
  const QuietHours(this.startMinutes, this.endMinutes);

  /// Minutes after local midnight.
  final int startMinutes, endMinutes;

  factory QuietHours.parse(String raw) {
    final p = raw.split('-');
    int mins(String s) {
      final h = s.split(':');
      return int.parse(h[0]) * 60 + int.parse(h[1]);
    }

    return QuietHours(mins(p[0]), mins(p[1]));
  }

  String get encoded => '${_hm(startMinutes)}-${_hm(endMinutes)}';
  static String _hm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  /// End of the quiet window holding [moment], or null if it is outside one.
  DateTime? windowEndAfter(DateTime moment) {
    if (startMinutes == endMinutes) return null;
    final l = moment.toLocal();
    final t = l.hour * 60 + l.minute;
    bool inside;
    var endDay = l.day;
    if (startMinutes < endMinutes) {
      inside = t >= startMinutes && t < endMinutes;
    } else if (t >= startMinutes) {
      inside = true;
      endDay += 1;
    } else {
      inside = t < endMinutes;
    }
    if (!inside) return null;
    return DateTime(
      l.year,
      l.month,
      endDay,
      endMinutes ~/ 60,
      endMinutes % 60,
    ).toUtc();
  }
}

/// Critical reminders always fire on time. Others wait until quiet hours end.
DateTime respectQuietHours(DateTime when, String urgency, QuietHours? quiet) {
  if (quiet == null || urgency == 'critical') return when;
  return quiet.windowEndAfter(when) ?? when;
}
