import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/core/errors/app_error.dart';
import 'package:omniassist/core/errors/error_codes.dart';
import 'package:omniassist/core/time/app_clock.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/time_blocks/time_block_rules.dart';
import 'package:omniassist/features/time_blocks/time_blocks_repository.dart';

DateTime t(int h, [int m = 0]) => DateTime.utc(2026, 10, 15, h, m);

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late TimeBlocksRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 10, 15, 8));
    repo = TimeBlocksRepository(db, clock);
  });
  tearDown(() => db.close());

  Future<BlockSaved> add(DateTime s, DateTime e, {String title = 'Focus'}) =>
      repo.create(
        ws: 'w1',
        title: title,
        category: 'focus',
        startsAt: s,
        endsAt: e,
      );

  test('transitions mirror the server table', () {
    expect(canTransition('planned', 'complete'), isTrue);
    expect(canTransition('complete', 'planned'), isTrue);
    expect(canTransition('complete', 'in_progress'), isFalse);
    expect(canTransition('cancelled', 'complete'), isFalse);
    expect(canTransition('complete', 'complete'), isTrue);
    expect(nextStatuses('complete'), ['complete', 'planned']);
  });

  test('inverted or empty range is rejected before saving', () async {
    for (final r in [(t(10), t(9)), (t(9), t(9))]) {
      await expectLater(
        add(r.$1, r.$2),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            ErrorCode.validationError,
          ),
        ),
      );
    }
    expect(await db.syncDao.pending(), isEmpty);
  });

  test('overlap warns but the block is still saved', () async {
    final a = await add(t(9), t(10), title: 'A');
    expect(a.overlaps, isEmpty);
    final b = await add(t(9, 30), t(10, 30), title: 'B');
    expect(b.overlaps.map((x) => x.id), [a.id]);
    expect((await db.timeBlockDao.inRange('w1', t(0), t(23))).length, 2);
  });

  test(
    'touching blocks do not overlap; cancelled blocks free their time',
    () async {
      final a = await add(t(9), t(10));
      expect((await add(t(10), t(11))).overlaps, isEmpty);
      await repo.edit(a.id, status: 'cancelled');
      expect((await add(t(9, 15), t(9, 45))).overlaps, isEmpty);
    },
  );

  test(
    'reschedule updates now, queues one update, and reports clashes',
    () async {
      final a = await add(t(9), t(10));
      await add(t(14), t(15), title: 'Other');
      final r = await repo.reschedule(a.id, t(14, 30), t(15, 30));
      expect(r.overlaps, hasLength(1));
      final row = (await repo.byId(a.id))!;
      expect(row.startsAt, t(14, 30));
      final updates = (await db.syncDao.pending()).where(
        (m) => m.operation == 'update',
      );
      expect(
        updates.single.payload,
        contains('"starts_at":"2026-10-15T14:30:00.000Z"'),
      );
      expect(
        row.syncState,
        'pending_create',
      ); // not uploaded yet, still a create
    },
  );

  test('a block must not exclude itself when checking overlap', () async {
    final a = await add(t(9), t(10));
    final r = await repo.edit(a.id, title: 'Renamed');
    expect(r.overlaps, isEmpty);
  });

  test('invalid status change is refused and queues nothing', () async {
    final a = await add(t(9), t(10));
    await repo.edit(a.id, status: 'complete');
    final before = (await db.syncDao.pending()).length;
    await expectLater(
      repo.edit(a.id, status: 'in_progress'),
      throwsA(
        isA<AppError>().having(
          (e) => e.code,
          'code',
          ErrorCode.domainRuleViolation,
        ),
      ),
    );
    expect((await db.syncDao.pending()).length, before);
  });

  test('block links to a task and survives a pulled update', () async {
    await db.taskDao.createWithOutbox(
      id: 'tk1',
      workspaceId: 'w1',
      title: 'Write',
      mutationId: 'm0',
      now: clock.now(),
    );
    final a = await repo.create(
      ws: 'w1',
      title: 'Write',
      category: 'focus',
      startsAt: t(9),
      endsAt: t(10),
      taskId: 'tk1',
    );
    expect((await repo.byId(a.id))!.taskId, 'tk1');
    await db.syncDao.ensureState('d1', 'u1');
    await db.syncDao.applyPulledPage(
      deviceId: 'd1',
      changes: [
        {
          'sequence': 1,
          'workspace_id': 'w1',
          'entity_type': 'time_block',
          'entity_id': a.id,
          'operation': 'update',
          'entity_version': 2,
          'payload': {'status': 'in_progress', 'category': 'meeting'},
        },
      ],
      nextCursor: 1,
      now: clock.now(),
    );
    final row = (await repo.byId(a.id))!;
    expect(
      (row.status, row.category, row.version),
      ('in_progress', 'meeting', 2),
    );
  });

  test('delete hides the block and queues a delete', () async {
    final a = await add(t(9), t(10));
    await repo.delete(a.id);
    expect(await db.timeBlockDao.inRange('w1', t(0), t(23)), isEmpty);
    expect((await db.syncDao.pending()).last.operation, 'delete');
  });
}
