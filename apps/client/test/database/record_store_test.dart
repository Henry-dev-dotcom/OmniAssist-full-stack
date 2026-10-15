import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 12);

  group('v1 to v2 upgrade', () {
    test('keeps tasks, drops the old milestones table, adds records', () async {
      final raw = sqlite3.openInMemory();
      // The v1 shapes the upgrade touches; the other v1 tables are unchanged by it.
      raw.execute('''
        CREATE TABLE projects (id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL,
          version INTEGER NOT NULL DEFAULT 0, sync_state TEXT NOT NULL DEFAULT 'synced',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
          name TEXT NOT NULL, category TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'planned',
          description TEXT, progress_value INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE milestones (id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects (id));
        CREATE TABLE tasks (id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL,
          version INTEGER NOT NULL DEFAULT 0, sync_state TEXT NOT NULL DEFAULT 'synced',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
          project_id TEXT NULL REFERENCES projects (id),
          milestone_id TEXT NULL REFERENCES milestones (id), parent_task_id TEXT NULL,
          title TEXT NOT NULL, description TEXT NULL, status TEXT NOT NULL DEFAULT 'inbox',
          priority TEXT NOT NULL DEFAULT 'normal', due_at TEXT NULL,
          estimated_minutes INTEGER NULL, recurrence_rule TEXT NULL, completed_at TEXT NULL);
        INSERT INTO tasks (id, workspace_id, created_at, updated_at, title)
          VALUES ('t1', 'w1', '2026-10-15T12:00:00.000Z', '2026-10-15T12:00:00.000Z', 'Keep me');
        PRAGMA user_version = 1;
      ''');
      final db = AppDatabase(NativeDatabase.opened(raw));
      addTearDown(db.close);

      expect((await db.taskDao.byId('t1'))!.title, 'Keep me');
      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table'",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(tables, contains('records'));
      expect(tables, isNot(contains('milestones')));
      // A task can now point at a record-backed milestone.
      await (db.update(db.tasks)..where((t) => t.id.equals('t1'))).write(
        const TasksCompanion(milestoneId: Value('m1')),
      );
      expect((await db.taskDao.byId('t1'))!.milestoneId, 'm1');
    });
  });

  group('record store', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Map<String, dynamic> data(RecordRow r) =>
        jsonDecode(r.data) as Map<String, dynamic>;

    test(
      'create, change and remove each queue one mutation in order',
      () async {
        final dao = db.recordDao;
        await dao.create(
          'w1',
          'milestone',
          'm1',
          {'project_id': 'p1', 'title': 'Chapter 1', 'due_at': now},
          'mu1',
          now,
        );
        await dao.change('m1', {'title': 'Chapter One'}, 'mu2', now);
        final row = (await dao.byId('m1'))!;
        expect(data(row), {
          'project_id': 'p1',
          'title': 'Chapter One',
          'due_at': '2026-10-15T12:00:00.000Z',
        });
        expect(row.syncState, 'pending_create'); // still unsent
        await dao.remove('m1', 'mu3', now);
        expect(await dao.ofType('w1', 'milestone'), isEmpty);
        final queued = await db.syncDao.pending();
        expect(queued.map((m) => m.operation), ['create', 'update', 'delete']);
        expect(queued.map((m) => jsonDecode(m.payload)), [
          {
            'project_id': 'p1',
            'title': 'Chapter 1',
            'due_at': '2026-10-15T12:00:00.000Z',
          },
          {'title': 'Chapter One'},
          <String, dynamic>{},
        ]);
      },
    );

    test('createAll is all or nothing', () async {
      await db.recordDao.create(
        'w1',
        'review_item',
        'dup',
        {'title': 'A'},
        'm0',
        now,
      );
      await expectLater(
        db.recordDao.createAll('w1', [
          (
            type: 'review_item',
            id: 'new1',
            data: {'title': 'B'},
            mutationId: 'm1',
          ),
          (
            type: 'review_item',
            id: 'dup',
            data: {'title': 'C'},
            mutationId: 'm2',
          ),
        ], now),
        throwsA(anything),
      );
      expect((await db.recordDao.ofType('w1', 'review_item')).length, 1);
      expect((await db.syncDao.pending()).length, 1);
    });

    test(
      'pull inserts, merges per field, keeps unsent edits, and deletes',
      () async {
        await db.syncDao.ensureState('d1', 'u1');
        Map<String, dynamic> change(
          int seq,
          String op,
          Map<String, dynamic>? p,
        ) => {
          'sequence': seq,
          'workspace_id': 'w1',
          'entity_type': 'analysis_record',
          'entity_id': 'a1',
          'operation': op,
          'entity_version': seq,
          'payload': p,
        };
        await db.syncDao.applyPulledPage(
          deviceId: 'd1',
          changes: [
            change(1, 'create', {'title': 'Model', 'status': 'planned'}),
          ],
          nextCursor: 1,
          now: now,
        );
        await db.recordDao.change('a1', {'title': 'My model'}, 'mu1', now);
        await db.syncDao.applyPulledPage(
          deviceId: 'd1',
          changes: [
            change(2, 'update', {'title': 'Server', 'status': 'failed'}),
          ],
          nextCursor: 2,
          now: now,
        );
        final row = (await db.recordDao.byId('a1'))!;
        expect(data(row), {'title': 'My model', 'status': 'failed'});
        expect(row.version, 2);
        await db.syncDao.applyPulledPage(
          deviceId: 'd1',
          changes: [change(3, 'delete', null)],
          nextCursor: 3,
          now: now,
        );
        expect(await db.recordDao.ofType('w1', 'analysis_record'), isEmpty);
      },
    );

    test(
      'accepted push marks the record synced with the server version',
      () async {
        await db.recordDao.create(
          'w1',
          'review',
          'r1',
          {'name': 'SLR'},
          'mu1',
          now,
        );
        final m = (await db.syncDao.pending()).single;
        await db.syncDao.applyPushResult(m, {
          'status': 'accepted',
          'entity_version': 1,
        }, now);
        final row = (await db.recordDao.byId('r1'))!;
        expect((row.syncState, row.version), ('synced', 1));
      },
    );
  });
}
