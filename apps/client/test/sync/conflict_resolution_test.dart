import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/sync/conflict_page.dart';

void main() {
  final now = DateTime.utc(2026, 10, 16, 9);
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('choices split into upload, server and combined text', () {
    final plan = planResolution(
      {'title': 'Mine', 'due_at': '2026-11-01', 'notes': 'my notes'},
      {'title': 'Theirs', 'due_at': '2026-12-01', 'notes': 'their notes'},
      {'title': Choice.mine, 'due_at': Choice.server, 'notes': Choice.both},
    );
    expect(plan.server, {'due_at': '2026-12-01'});
    expect(plan.local['title'], 'Mine');
    expect(plan.local['notes'], contains('their notes'));
    expect(plan.local['notes'], contains('my notes'));
  });

  test(
    'resolving applies server values, re-uploads mine on the server version, '
    'and clears the stuck mutation',
    () async {
      final dao = db.recordDao;
      await dao.create(
        'w1',
        'milestone',
        'm1',
        {'title': 'A', 'due_at': null},
        'mu0',
        now,
      );
      final created = (await db.syncDao.pending()).single;
      await db.syncDao.applyPushResult(created, {
        'status': 'accepted',
        'entity_version': 1,
      }, now);
      await dao.change(
        'm1',
        {'title': 'Mine', 'due_at': '2026-11-01T00:00:00Z'},
        'mu1',
        now,
      );
      final edit = (await db.syncDao.pending()).single;
      await db.syncDao.applyPushResult(edit, {
        'status': 'conflict',
        'conflict_id': 'c1',
        'server': {
          'title': 'Theirs',
          'due_at': '2026-12-01T00:00:00Z',
          'version': 3,
        },
      }, now);
      final conflict = (await db.syncDao.watchOpenConflicts().first).single;

      await db.syncDao.resolveConflict(
        conflict: conflict,
        local: {'title': 'Mine'},
        server: {'due_at': '2026-12-01T00:00:00Z'},
        serverVersion: 3,
        mutationId: 'mu2',
        now: now,
      );

      final row = (await dao.byId('m1'))!;
      expect(jsonDecode(row.data), {
        'title': 'Mine',
        'due_at': '2026-12-01T00:00:00Z',
      });
      expect((row.version, row.syncState), (3, 'pending_update'));
      final queued = await db.syncDao.pending();
      expect(queued.map((m) => (m.mutationId, m.baseVersion)), [('mu2', 3)]);
      expect(jsonDecode(queued.single.payload), {'title': 'Mine'});
      expect(await db.syncDao.watchOpenConflicts().first, isEmpty);
      expect(
        (await db.select(db.outboxMutations).get()).where(
          (m) => m.status == 'conflict',
        ),
        isEmpty,
      );
    },
  );

  test('wipe removes everything on the device', () async {
    await db.recordDao.create(
      'w1',
      'review',
      'r1',
      {'name': 'SLR'},
      'mu1',
      now,
    );
    await db.taskDao.createWithOutbox(
      id: 't1',
      workspaceId: 'w1',
      title: 'T',
      mutationId: 'mu2',
      now: now,
    );
    await db.wipe();
    for (final t in db.allTables) {
      expect(await db.select(t).get(), isEmpty, reason: t.actualTableName);
    }
  });
}
