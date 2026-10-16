import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/features/tasks/recurrence.dart';

void main() {
  test('rules round-trip and describe themselves', () {
    final r = parseRule('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR');
    expect(r.toRule(), 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR');
    expect(r.describe(), 'Every 2 weeks on Mon, Fri');
    expect(parseRule('FREQ=DAILY').describe(), 'Every day');
  });

  test('invalid rules give field messages like the server', () {
    for (final (rule, why) in [
      ('FREQ=HOURLY', 'FREQ must be'),
      ('FREQ=DAILY;INTERVAL=0', 'INTERVAL'),
      ('FREQ=DAILY;BYDAY=MO', 'only with FREQ=WEEKLY'),
      ('FREQ=WEEKLY;BYDAY=MO,MO', 'BYDAY lists'),
      ('FREQ=DAILY;COUNT=2', 'Unsupported part: COUNT'),
      ('every day', 'KEY=VALUE'),
    ]) {
      expect(
        () => parseRule(rule),
        throwsA(
          isA<FormatException>().having((e) => e.message, rule, contains(why)),
        ),
      );
    }
  });

  group('next occurrence keeps the time of day', () {
    final wed = DateTime(2026, 10, 14, 9, 30); // a Wednesday
    test('daily and every 3 days', () {
      expect(
        nextOccurrence(wed, parseRule('FREQ=DAILY')),
        DateTime(2026, 10, 15, 9, 30),
      );
      expect(
        nextOccurrence(wed, parseRule('FREQ=DAILY;INTERVAL=3')),
        DateTime(2026, 10, 17, 9, 30),
      );
    });
    test('weekly on chosen days, later this week or the next active week', () {
      final r = parseRule('FREQ=WEEKLY;BYDAY=MO,FR');
      expect(nextOccurrence(wed, r), DateTime(2026, 10, 16, 9, 30)); // Fri
      final fri = DateTime(2026, 10, 16, 9, 30);
      expect(nextOccurrence(fri, r), DateTime(2026, 10, 19, 9, 30)); // next Mon
      final biweekly = parseRule('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO');
      expect(nextOccurrence(fri, biweekly), DateTime(2026, 10, 26, 9, 30));
      expect(
        nextOccurrence(wed, parseRule('FREQ=WEEKLY')),
        DateTime(2026, 10, 21, 9, 30),
      );
    });
    test('monthly clamps to the last day; yearly handles leap days', () {
      final jan31 = DateTime(2026, 1, 31, 8);
      expect(
        nextOccurrence(jan31, parseRule('FREQ=MONTHLY')),
        DateTime(2026, 2, 28, 8),
      );
      final leap = DateTime(2028, 2, 29, 8);
      expect(
        nextOccurrence(leap, parseRule('FREQ=YEARLY')),
        DateTime(2029, 2, 28, 8),
      );
    });
  });
}
