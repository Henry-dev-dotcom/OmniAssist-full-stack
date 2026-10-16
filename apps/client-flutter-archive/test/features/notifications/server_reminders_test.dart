import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniassist/core/net/api_client.dart';
import 'package:omniassist/core/time/app_clock.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/notifications/notification_gateway.dart';
import 'package:omniassist/features/notifications/notification_repository.dart';
import 'package:omniassist/features/notifications/server_reminders.dart';

void main() {
  late AppDatabase db;
  late bool online;
  late List<(String, Object?)> calls;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    online = false;
    calls = [];
  });
  tearDown(() => db.close());

  ServerReminders mirror() => ServerReminders(
    db,
    ApiClient(
      baseUrl: 'http://t/api/v1',
      client: MockClient((r) async {
        if (!online) throw http.ClientException('offline');
        calls.add((r.url.path, jsonDecode(r.body)));
        return http.Response(
          jsonEncode({'data': <Object>[], 'meta': <String, Object>{}}),
          200,
        );
      }),
    ),
  );

  test('offline reminders wait, then reach the server after sync', () async {
    final clock = FixedClock(DateTime.utc(2026, 10, 16, 8));
    final server = mirror();
    final repo = NotificationRepository(db, clock, const NoopGateway(), server);
    await db.taskDao.createWithOutbox(
      id: 't1',
      workspaceId: 'w1',
      title: 'Submit form',
      dueAt: DateTime.utc(2026, 10, 20, 17),
      mutationId: 'm1',
      now: clock.now(),
    );
    final task = (await db.taskDao.byId('t1'))!;

    await repo.setForTask(task, ['1h', '1d'], urgency: 'high');
    await Future<void>.delayed(
      Duration.zero,
    ); // the mirror runs in the background
    await server.mirror('t1'); // settle it deterministically for the test
    expect(calls, isEmpty);
    expect(await db.reminderDao.setting('server_reminders.pending'), '["t1"]');

    online = true;
    await server.flush();
    expect(calls.single.$1, '/api/v1/tasks/t1/reminders');
    final body = calls.single.$2! as Map<String, dynamic>;
    expect((body['offsets'] as List).toSet(), {'1h', '1d'});
    expect((body['urgency'], body['channel']), ('high', 'push'));
    expect(await db.reminderDao.setting('server_reminders.pending'), '[]');
  });
}
