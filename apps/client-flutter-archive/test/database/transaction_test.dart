import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/database/app_database.dart';

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 10, 14);
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('task and outbox mutation commit together', () async {
    await db.taskDao.createWithOutbox(
      id: 't1',
      workspaceId: 'w1',
      title: 'Write methods',
      mutationId: 'm1',
      now: now,
    );
    expect(await db.taskDao.byId('t1'), isNotNull);
    expect(await db.syncDao.pending(), hasLength(1));
  });

  test('a failed outbox insert rolls back the task', () async {
    await db.taskDao.createWithOutbox(
      id: 't1',
      workspaceId: 'w1',
      title: 'First',
      mutationId: 'm1',
      now: now,
    );
    // Same mutation ID: the outbox insert fails after the task insert succeeded.
    await expectLater(
      db.taskDao.createWithOutbox(
        id: 't2',
        workspaceId: 'w1',
        title: 'Second',
        mutationId: 'm1',
        now: now,
      ),
      throwsA(anything),
    );
    expect(await db.taskDao.byId('t2'), isNull);
    expect(await db.syncDao.pending(), hasLength(1));
  });
}
