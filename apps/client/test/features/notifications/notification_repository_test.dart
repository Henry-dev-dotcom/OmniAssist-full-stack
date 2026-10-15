import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/core/errors/app_error.dart';
import 'package:omniassist/core/errors/error_codes.dart';
import 'package:omniassist/core/time/app_clock.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/notifications/notification_gateway.dart';
import 'package:omniassist/features/notifications/notification_repository.dart';
import 'package:omniassist/features/notifications/reminder_rules.dart';
import 'package:omniassist/features/tasks/tasks_repository.dart';

class FakeGateway implements NotificationGateway {
  FakeGateway({this.permitted = true, this.fail = false});
  bool permitted, fail;
  final shown = <String>[];
  @override
  Future<bool> isPermitted() async => permitted;
  @override
  Future<void> show({
    required String id,
    required String title,
    required String urgency,
  }) async {
    if (fail) throw StateError('os refused');
    shown.add(title);
  }
}

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late FakeGateway gw;
  late NotificationRepository repo;
  late TasksRepository tasks;

  // Midday local, so default quiet hours do not interfere unless a test wants them to.
  final base = DateTime(2026, 10, 15, 12).toUtc();
  DateTime inHours(int h) => base.add(Duration(hours: h));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    clock = FixedClock(base);
    gw = FakeGateway();
    repo = NotificationRepository(db, clock, gw);
    tasks = TasksRepository(db, clock, repo);
    await repo.setQuietHours(null);
  });
  tearDown(() => db.close());

  Future<Task> mk(String id, {DateTime? due, String status = 'planned'}) async {
    await db.taskDao.createWithOutbox(
      id: id,
      workspaceId: 'w',
      title: 'Task $id',
      mutationId: 'm$id',
      now: base,
    );
    await db.taskDao.updateWithOutbox(
      id: id,
      changes: {'status': status, 'due_at': ?due},
      mutationId: 'u$id',
      now: base,
    );
    return (await db.taskDao.byId(id))!;
  }

  test('scheduling skips past times and replaces earlier reminders', () async {
    final t = await mk('a', due: inHours(48));
    expect(await repo.setForTask(t, ['1h', '1d', '1h']), 2);
    expect(await repo.setForTask(t, ['15m']), 1);
    final open = await repo.forTask('a');
    expect(
      open.where((r) => r.status == 'scheduled').map((r) => r.offsetSpec),
      ['15m'],
    );
    final soon = await mk('b', due: inHours(1));
    expect(await repo.setForTask(soon, ['1d', '15m']), 1);
  });

  test('rules: no due date, finished task, bad input', () async {
    final undated = await mk('a');
    final done = await mk('b', due: inHours(48), status: 'complete');
    final ok = await mk('c', due: inHours(48));
    for (final f in [
      () => repo.setForTask(undated, ['1h']),
      () => repo.setForTask(done, ['1h']),
    ]) {
      await expectLater(
        f(),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            ErrorCode.domainRuleViolation,
          ),
        ),
      );
    }
    await expectLater(repo.setForTask(ok, ['2h']), throwsA(isA<AppError>()));
    await expectLater(
      repo.setForTask(ok, ['1h'], urgency: 'loud'),
      throwsA(isA<AppError>()),
    );
  });

  test('completing, clearing or moving the due date fixes reminders', () async {
    final t = await mk('a', due: inHours(72));
    await repo.setForTask(t, ['1d']);
    final before = (await repo.forTask('a')).single.remindAt;

    final moved = (await db.taskDao.byId('a'))!;
    await tasks.edit(
      moved,
      TaskEdit(
        title: moved.title,
        description: null,
        status: moved.status,
        priority: moved.priority,
        dueAt: inHours(120),
        projectId: null,
      ),
    );
    final after = (await repo.forTask('a')).single.remindAt;
    expect(after.isAfter(before), isTrue);
    expect(after, inHours(120 - 24));

    await tasks.setDone('a', true);
    expect(await repo.forTask('a'), isEmpty);
    await tasks.setDone('a', false);
    expect(
      await repo.forTask('a'),
      isEmpty,
      reason: 'reopening does not revive old reminders',
    );
  });

  test('quiet hours shift reminders, but not critical ones', () async {
    await repo.setQuietHours(const QuietHours(22 * 60, 7 * 60));
    final due = DateTime(2026, 10, 17, 23).toUtc();
    final t = await mk('a', due: due);
    await repo.setForTask(t, ['at_due']);
    expect((await repo.forTask('a')).single.remindAt.toLocal().hour, 7);
    await repo.setForTask(t, ['at_due'], urgency: 'critical');
    expect((await repo.forTask('a')).single.remindAt.toLocal().hour, 23);
  });

  test(
    'delivery: due reminders are sent once and shown through the gateway',
    () async {
      final t = await mk('a', due: inHours(5));
      await repo.setForTask(t, ['1h']);
      expect(await repo.deliverDue(), 0);
      clock.advance(const Duration(hours: 4));
      expect(await repo.deliverDue(), 1);
      expect(await repo.deliverDue(), 0);
      expect(gw.shown, ['Task a']);
      final row = (await repo.forTask('a')).single;
      expect((row.status, row.sentAt), ('sent', clock.now()));
    },
  );

  test('denied OS permission still lands in the in-app center', () async {
    gw.permitted = false;
    final t = await mk('a', due: inHours(5));
    await repo.setForTask(t, ['1h']);
    clock.advance(const Duration(hours: 4));
    await repo.deliverDue();
    expect(gw.shown, isEmpty);
    expect(await repo.osPermitted(), isFalse);
    final center = await repo.watchCenter('w').first;
    expect(center.single.status, 'sent');
  });

  test('a gateway failure is recorded as failed', () async {
    gw.fail = true;
    final t = await mk('a', due: inHours(5));
    await repo.setForTask(t, ['1h']);
    clock.advance(const Duration(hours: 4));
    await repo.deliverDue();
    final r = (await repo.forTask('a')).single;
    expect(r.status, 'failed');
    expect(r.failureReason, contains('os refused'));
  });

  test('a task finished by sync is skipped at delivery', () async {
    final t = await mk('a', due: inHours(5));
    await repo.setForTask(t, ['1h']);
    // Simulate a pulled change that bypassed the repository.
    await db.taskDao.updateWithOutbox(
      id: 'a',
      changes: {'status': 'complete'},
      mutationId: 'x',
      now: base,
    );
    clock.advance(const Duration(hours: 4));
    expect(await repo.deliverDue(), 0);
    expect(gw.shown, isEmpty);
  });

  test('quiet hours that begin after scheduling defer delivery', () async {
    final t = await mk('a', due: inHours(5));
    await repo.setForTask(t, ['1h']);
    await repo.setQuietHours(const QuietHours(0, 23 * 60 + 59));
    clock.advance(const Duration(hours: 4));
    expect(await repo.deliverDue(), 0);
    expect((await repo.forTask('a')).single.status, 'scheduled');
  });

  test(
    'states: read, snooze (returns unread), ack, dismiss, and invalid moves',
    () async {
      final t = await mk('a', due: inHours(5));
      await repo.setForTask(t, ['1h']);
      clock.advance(const Duration(hours: 4));
      await repo.deliverDue();
      final id = (await repo.forTask('a')).single.id;

      expect(await repo.watchUnread('w').first, 1);
      await repo.markRead(id);
      expect(await repo.watchUnread('w').first, 0);

      await repo.snooze(id, minutes: 30);
      expect((await repo.forTask('a')).single.status, 'snoozed');
      await expectLater(repo.acknowledge(id), throwsA(isA<AppError>()));

      clock.advance(const Duration(minutes: 31));
      expect(await repo.deliverDue(), 1);
      expect((await repo.forTask('a')).single.readAt, isNull);

      await repo.acknowledge(id);
      expect((await repo.forTask('a')).single.status, 'acted_on');
      await expectLater(repo.dismiss(id), throwsA(isA<AppError>()));
      await expectLater(
        repo.dismiss('nope'),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', ErrorCode.notFound),
        ),
      );
    },
  );

  test('quiet hours setting persists; default is on', () async {
    await db.reminderDao.putSetting('quiet_hours', 'off');
    expect(await repo.quietHours(), isNull);
    await repo.setQuietHours(const QuietHours(21 * 60, 6 * 60));
    expect((await repo.quietHours())!.encoded, '21:00-06:00');
    final fresh = NotificationRepository(
      AppDatabase(NativeDatabase.memory()),
      clock,
      gw,
    );
    expect((await fresh.quietHours())!.encoded, '22:00-07:00');
  });
}
