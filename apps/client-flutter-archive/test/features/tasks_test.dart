import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/core/time/app_clock.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/tasks/tasks_repository.dart';

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late TasksRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 10, 15, 12));
    repo = TasksRepository(db, clock);
  });
  tearDown(() => db.close());

  Future<String> captured(String title) async {
    await repo.capture('w1', title);
    return (await db.taskDao.watchInbox('w1').first)
        .firstWhere((t) => t.title == title)
        .id;
  }

  test('quick capture lands in the Inbox and queues a create', () async {
    await repo.capture('w1', '  Email supervisor  ');
    final t = (await repo.watchInbox('w1').first).single;
    expect(
      (t.title, t.status, t.syncState),
      ('Email supervisor', 'inbox', 'pending_create'),
    );
    final m = (await db.syncDao.pending()).single;
    expect((m.entityType, m.operation), ('task', 'create'));
  });

  test(
    'completing records a time, queues an update, and can be undone',
    () async {
      final id = await captured('A');
      await repo.setDone(id, true);
      var t = (await db.taskDao.byId(id))!;
      expect((t.status, t.completedAt), ('complete', clock.now()));
      expect(await repo.watchInbox('w1').first, isEmpty);
      final updates = (await db.syncDao.pending()).where(
        (m) => m.operation == 'update',
      );
      expect(updates.single.payload, contains('"status":"complete"'));
      await repo.setDone(id, false);
      t = (await db.taskDao.byId(id))!;
      expect((t.status, t.completedAt), ('planned', null));
    },
  );

  test('moving to a project links it and plans the task', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            workspaceId: 'w1',
            name: 'Thesis',
            category: 'thesis',
            createdAt: clock.now(),
            updatedAt: clock.now(),
          ),
        );
    final id = await captured('Chapter 1');
    await repo.moveToProject(id, 'p1');
    final t = (await db.taskDao.byId(id))!;
    expect((t.projectId, t.status), ('p1', 'planned'));
  });

  test('archive removes the task from the Inbox', () async {
    final id = await captured('Old idea');
    await repo.archive(id);
    expect(await repo.watchInbox('w1').first, isEmpty);
  });

  test('Today shows overdue and due-today open tasks only', () async {
    Future<void> add(String id, DateTime? due, {String status = 'planned'}) =>
        db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: id,
                workspaceId: 'w1',
                title: id,
                status: Value(status),
                dueAt: Value(due),
                createdAt: clock.now(),
                updatedAt: clock.now(),
              ),
            );
    await add('overdue', DateTime.utc(2026, 10, 10));
    await add('today', DateTime.utc(2026, 10, 15, 12));
    await add('tomorrow', DateTime.utc(2026, 10, 17));
    await add('nodate', null);
    await add('done', DateTime.utc(2026, 10, 15), status: 'complete');
    final ids = (await repo.watchToday('w1').first).map((t) => t.id).toList();
    expect(ids, ['overdue', 'today']);
  });

  test(
    'pulled task changes apply, and local unsent edits win per field',
    () async {
      final id = await captured('Local title');
      await repo.setDone(id, true); // pending: status
      await db.syncDao.ensureState('d1', 'u1');
      await db.syncDao.applyPulledPage(
        deviceId: 'd1',
        changes: [
          {
            'sequence': 1,
            'workspace_id': 'w1',
            'entity_type': 'task',
            'entity_id': id,
            'operation': 'update',
            'entity_version': 3,
            'payload': {
              'status': 'snoozed',
              'title': 'Server title',
              'due_at': '2026-10-20T09:00:00Z',
            },
          },
        ],
        nextCursor: 1,
        now: clock.now(),
      );
      final t = (await db.taskDao.byId(id))!;
      expect(t.status, 'complete'); // unsent local edit kept
      expect(t.title, 'Server title');
      expect(t.dueAt, DateTime.utc(2026, 10, 20, 9));
      expect(t.version, 3);
    },
  );

  test(
    'a task created elsewhere appears after pull, then goes on delete',
    () async {
      Map<String, dynamic> change(
        int seq,
        String op,
        Map<String, dynamic>? p,
      ) => {
        'sequence': seq,
        'workspace_id': 'w1',
        'entity_type': 'task',
        'entity_id': 't9',
        'operation': op,
        'entity_version': seq,
        'payload': p,
      };
      await db.syncDao.ensureState('d1', 'u1');
      await db.syncDao.applyPulledPage(
        deviceId: 'd1',
        changes: [
          change(1, 'create', {
            'title': 'From phone',
            'status': 'inbox',
            'updated_at': '2026-10-14T00:00:00Z',
          }),
        ],
        nextCursor: 1,
        now: clock.now(),
      );
      expect((await repo.watchInbox('w1').first).single.title, 'From phone');
      await db.syncDao.applyPulledPage(
        deviceId: 'd1',
        changes: [change(2, 'delete', null)],
        nextCursor: 2,
        now: clock.now(),
      );
      expect(await repo.watchInbox('w1').first, isEmpty);
    },
  );

  test(
    'accepted push marks a task synced and stores the server version',
    () async {
      final id = await captured('Sync me');
      final m = (await db.syncDao.pending()).single;
      await db.syncDao.applyPushResult(m, {
        'status': 'accepted',
        'entity_version': 1,
      }, clock.now());
      final t = (await db.taskDao.byId(id))!;
      expect((t.syncState, t.version), ('synced', 1));
    },
  );

  group('edit', () {
    TaskEdit same(Task t) => TaskEdit(
      title: t.title,
      description: t.description,
      status: t.status,
      priority: t.priority,
      dueAt: t.dueAt,
      projectId: t.projectId,
    );

    test('saving without changes queues nothing', () async {
      final id = await captured('A');
      final t = (await db.taskDao.byId(id))!;
      final before = (await db.syncDao.pending()).length;
      expect(await repo.edit(t, same(t)), isFalse);
      expect((await db.syncDao.pending()).length, before);
    });

    test('only changed fields are sent, and they apply locally', () async {
      final id = await captured('A');
      final t = (await db.taskDao.byId(id))!;
      final due = dueFromDate(DateTime(2026, 11, 2));
      final e = TaskEdit(
        title: ' A2 ',
        description: 'notes',
        status: t.status,
        priority: 'high',
        dueAt: due,
        projectId: null,
      );
      expect(await repo.edit(t, e), isTrue);
      final u = (await db.taskDao.byId(id))!;
      expect(
        (u.title, u.description, u.priority, u.dueAt),
        ('A2', 'notes', 'high', due),
      );
      final m = (await db.syncDao.pending()).last;
      expect(m.operation, 'update');
      expect(m.payload, isNot(contains('status')));
      expect(m.payload, contains('"priority":"high"'));
      expect(m.payload, contains('"due_at":"${due.toIso8601String()}"'));
    });

    test('clearing due date and description sends nulls', () async {
      final id = await captured('A');
      var t = (await db.taskDao.byId(id))!;
      await repo.edit(
        t,
        TaskEdit(
          title: t.title,
          description: 'x',
          status: t.status,
          priority: t.priority,
          dueAt: dueFromDate(DateTime(2026, 11, 2)),
          projectId: null,
        ),
      );
      t = (await db.taskDao.byId(id))!;
      await repo.edit(
        t,
        TaskEdit(
          title: t.title,
          description: '  ',
          status: t.status,
          priority: t.priority,
          dueAt: null,
          projectId: null,
        ),
      );
      final u = (await db.taskDao.byId(id))!;
      expect((u.description, u.dueAt), (null, null));
      final m = (await db.syncDao.pending()).last;
      expect(m.payload, contains('"due_at":null'));
      expect(m.payload, contains('"description":null'));
    });

    test(
      'empty-description edit on a task with none is not a change',
      () async {
        final id = await captured('A');
        final t = (await db.taskDao.byId(id))!;
        final e = TaskEdit(
          title: t.title,
          description: '',
          status: t.status,
          priority: t.priority,
          dueAt: null,
          projectId: null,
        );
        expect(await repo.edit(t, e), isFalse);
      },
    );
  });

  test(
    'linking an inbox task to a milestone moves it into that project',
    () async {
      await db.projectDao.createWithOutbox(
        id: 'p1',
        workspaceId: 'w1',
        name: 'Thesis',
        category: 'thesis',
        mutationId: 'mp',
        now: clock.now(),
      );
      final id = await captured('Read paper');
      await repo.linkMilestone(id, 'm1', projectId: 'p1');
      final t = (await db.taskDao.byId(id))!;
      expect((t.milestoneId, t.projectId, t.status), ('m1', 'p1', 'planned'));
      await repo.linkMilestone(id, null);
      expect(
        (await db.taskDao.byId(id))!.projectId,
        'p1',
      ); // unlinking keeps the project
    },
  );

  Future<Task> recurring(String rule) async {
    final id = await captured('Lab meeting');
    final before = (await db.taskDao.byId(id))!;
    await repo.edit(
      before,
      TaskEdit(
        title: before.title,
        description: null,
        status: 'planned',
        priority: 'normal',
        dueAt: DateTime(2026, 10, 14, 10).toUtc(), // a Wednesday
        projectId: null,
        tags: const ['lab', 'weekly'],
        recurrenceRule: rule,
      ),
    );
    return (await db.taskDao.byId(id))!;
  }

  test(
    'completing a recurring task creates exactly one next occurrence',
    () async {
      final t = await recurring('FREQ=WEEKLY;BYDAY=WE,FR');
      expect(t.recurrenceRule, 'FREQ=WEEKLY;BYDAY=WE,FR');
      expect(tagsOf(t), ['lab', 'weekly']);
      await repo.setDone(t.id, true);
      final all = await db.select(db.tasks).get();
      final done = all.singleWhere((x) => x.id == t.id);
      final next = all.singleWhere((x) => x.id != t.id);
      expect((done.status, done.recurrenceRule), ('complete', null));
      expect(next.status, 'planned');
      expect(next.dueAt!.toLocal(), DateTime(2026, 10, 16, 10)); // Friday
      expect(next.recurrenceRule, t.recurrenceRule);
      expect(tagsOf(next), ['lab', 'weekly']);
      // Unticking and ticking again never makes a third task.
      await repo.setDone(t.id, false);
      await repo.setDone(t.id, true);
      expect(await db.select(db.tasks).get(), hasLength(2));
    },
  );

  test('subtasks join the parent and clearing a rule removes it', () async {
    final t = await recurring('FREQ=DAILY');
    await repo.addSubtask(t, ' Book room ');
    final subs = await repo.watchSubtasks(t).first;
    expect((subs.single.title, subs.single.parentTaskId), ('Book room', t.id));
    await repo.edit(
      t,
      TaskEdit(
        title: t.title,
        description: null,
        status: t.status,
        priority: t.priority,
        dueAt: t.dueAt,
        projectId: null,
        recurrenceRule: '',
      ),
    );
    expect((await db.taskDao.byId(t.id))!.recurrenceRule, isNull);
    final last = (await db.syncDao.pending()).last;
    expect(last.payload, '{"recurrence_rule":null}');
  });
}
