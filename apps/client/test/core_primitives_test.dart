import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/core/errors/app_error.dart';
import 'package:omniassist/core/errors/error_codes.dart';
import 'package:omniassist/core/ids/entity_ids.dart';
import 'package:omniassist/core/time/app_clock.dart';

void main() {
  test('uuid7 has version 7 and sorts by time', () {
    final a = newUuid7(now: DateTime.utc(2026, 1, 1));
    final b = newUuid7(now: DateTime.utc(2026, 1, 2));
    expect(a[14], '7');
    expect(a.compareTo(b), lessThan(0));
  });

  test('unknown error code maps to internalError', () {
    expect(ErrorCode.fromWire('FUTURE_CODE'), ErrorCode.internalError);
  });

  test('envelope parses', () {
    final e = AppError.fromEnvelope({
      'error': {'code': 'FORBIDDEN', 'message': 'No.', 'request_id': 'req_1'},
    });
    expect(e.code, ErrorCode.forbidden);
    expect(e.requestId, 'req_1');
  });

  test('timestamps serialize as UTC', () {
    expect(toUtcIso(DateTime.utc(2026, 10, 14, 18)), endsWith('Z'));
    expect(FixedClock(DateTime.utc(2026)).now().isUtc, isTrue);
  });
}
