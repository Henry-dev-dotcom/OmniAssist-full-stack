import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/core/time/app_clock.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/time_blocks/calendar_math.dart';
import 'package:omniassist/features/time_blocks/time_blocks_repository.dart';

void main() {
  test('week starts on Monday', () {
    expect(weekStart(DateTime(2026, 10, 15)), DateTime(2026, 10, 12));
    expect(weekStart(DateTime(2026, 10, 18)), DateTime(2026, 10, 12));
    expect(weekStart(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
  });

  test('month grid is whole Monday-first weeks covering the month', () {
    final cells = monthCells(DateTime(2026, 10, 15));
    expect(cells.length % 7, 0);
    expect(cells.first.weekday, DateTime.monday);
    expect(cells.first.isAfter(DateTime(2026, 10, 1)), isFalse);
    expect(cells.last.isBefore(DateTime(2026, 10, 31)), isFalse);
  });

  test('nextFreeStart skips busy blocks and cancelled ones', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TimeBlocksRepository(
      db,
      FixedClock(DateTime.utc(2026, 10, 15)),
    );
    DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 15, h, m);
    final a = await repo.create(
      ws: 'w',
      title: 'A',
      category: 'focus',
      startsAt: at(9),
      endsAt: at(10),
    );
    await repo.create(
      ws: 'w',
      title: 'B',
      category: 'focus',
      startsAt: at(10),
      endsAt: at(11),
    );
    var rows = await db.timeBlockDao.inRange(
      'w',
      at(0).toUtc(),
      at(23).toUtc(),
    );
    expect(nextFreeStart(rows, at(9), const Duration(hours: 1)), at(11));
    await repo.edit(a.id, status: 'cancelled');
    rows = await db.timeBlockDao.inRange('w', at(0).toUtc(), at(23).toUtc());
    expect(nextFreeStart(rows, at(9), const Duration(hours: 1)), at(9));
  });

  test('unscheduled tray lists open tasks without a block', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = FixedClock(DateTime.utc(2026, 10, 15));
    final repo = TimeBlocksRepository(db, clock);
    for (final id in ['t1', 't2']) {
      await db.taskDao.createWithOutbox(
        id: id,
        workspaceId: 'w',
        title: id,
        mutationId: 'm$id',
        now: clock.now(),
      );
    }
    await repo.create(
      ws: 'w',
      title: 't1',
      category: 'focus',
      startsAt: DateTime.utc(2026, 10, 15, 9),
      endsAt: DateTime.utc(2026, 10, 15, 10),
      taskId: 't1',
    );
    final open = await repo.watchUnscheduled('w').first;
    expect(open.map((t) => t.id), ['t2']);
  });
}
