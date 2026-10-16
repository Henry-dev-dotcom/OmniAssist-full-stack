import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/features/notifications/reminder_rules.dart';

/// Tests build expected values with local-time constructors so they hold in any zone.
DateTime local(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime(y, m, d, h, min).toUtc();

void main() {
  group('offsets', () {
    final due = DateTime.utc(2026, 10, 20, 12);
    test('presets subtract from due', () {
      expect(remindAt(due, 'at_due'), due);
      expect(remindAt(due, '15m'), DateTime.utc(2026, 10, 20, 11, 45));
      expect(remindAt(due, '1h'), DateTime.utc(2026, 10, 20, 11));
      expect(remindAt(due, '1d'), DateTime.utc(2026, 10, 19, 12));
      expect(remindAt(due, 'custom:90'), DateTime.utc(2026, 10, 20, 10, 30));
    });

    test('morning offsets land at 9:00 local on the right local day', () {
      final d = DateTime(2026, 10, 20, 17).toUtc(); // 17:00 local
      expect(remindAt(d, 'morning_of'), local(2026, 10, 20, 9));
      expect(remindAt(d, 'morning_before'), local(2026, 10, 19, 9));
      // Month boundary.
      final first = DateTime(2026, 11, 1, 10).toUtc();
      expect(remindAt(first, 'morning_before'), local(2026, 10, 31, 9));
    });

    test('bad offsets are rejected', () {
      for (final bad in [
        '',
        '2h',
        'custom:',
        'custom:-5',
        'custom:x',
        'custom:999999999',
      ]) {
        expect(isValidOffset(bad), isFalse, reason: bad);
        expect(() => remindAt(DateTime.utc(2026), bad), throwsArgumentError);
      }
      expect(isValidOffset('custom:0'), isTrue);
    });
  });

  group('quiet hours', () {
    const night = QuietHours(22 * 60, 7 * 60);

    test('wrap midnight and defer to the end', () {
      expect(
        respectQuietHours(local(2026, 10, 20, 23, 30), 'normal', night),
        local(2026, 10, 21, 7),
      );
      expect(
        respectQuietHours(local(2026, 10, 21, 3), 'normal', night),
        local(2026, 10, 21, 7),
      );
    });

    test('outside the window is unchanged; edges are half-open', () {
      final noon = local(2026, 10, 20, 12);
      expect(respectQuietHours(noon, 'normal', night), noon);
      final seven = local(2026, 10, 20, 7);
      expect(respectQuietHours(seven, 'normal', night), seven);
      expect(
        respectQuietHours(local(2026, 10, 20, 22), 'low', night),
        local(2026, 10, 21, 7),
      );
    });

    test('critical ignores quiet hours', () {
      final at = local(2026, 10, 20, 23, 30);
      expect(respectQuietHours(at, 'critical', night), at);
    });

    test('same-day window, empty window, and no window', () {
      const lunch = QuietHours(12 * 60, 13 * 60);
      expect(
        respectQuietHours(local(2026, 10, 20, 12, 30), 'normal', lunch),
        local(2026, 10, 20, 13),
      );
      const none = QuietHours(8 * 60, 8 * 60);
      final at = local(2026, 10, 20, 8);
      expect(respectQuietHours(at, 'normal', none), at);
      expect(respectQuietHours(at, 'normal', null), at);
    });

    test('encodes and parses', () {
      expect(night.encoded, '22:00-07:00');
      final q = QuietHours.parse('21:30-06:15');
      expect((q.startMinutes, q.endMinutes), (21 * 60 + 30, 6 * 60 + 15));
    });
  });
}
