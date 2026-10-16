import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/app/providers.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/auth/auth_controller.dart';
import 'package:omniassist/features/auth/auth_repository.dart';
import 'package:omniassist/features/time_blocks/calendar_math.dart';
import 'package:omniassist/features/time_blocks/calendar_screen.dart';

class _SignedIn extends AuthController {
  @override
  Future<Session?> build() async =>
      const Session(userId: 'u1', workspaceId: 'w1');
}

void main() {
  testWidgets('dragging a block to another day in the week moves it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final today = dayOf(DateTime.now());
    // Another day in the same week as today.
    final target = today.weekday == 1 ? addDays(today, 1) : addDays(today, -1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(_SignedIn.new),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );
    await tester.runAsync(
      () => db.timeBlockDao.createWithOutbox(
        id: 'b1',
        workspaceId: 'w1',
        title: 'Deep work',
        category: 'focus',
        startsAt: DateTime(today.year, today.month, today.day, 10).toUtc(),
        endsAt: DateTime(today.year, today.month, today.day, 12).toUtc(),
        mutationId: 'm1',
        now: DateTime.now().toUtc(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();

    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final chip = find.textContaining('Deep work');
    final row = find.text('${names[target.weekday - 1]} ${target.day}');
    expect(chip, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(chip));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    final moved = (await tester.runAsync(() => db.timeBlockDao.byId('b1')))!;
    expect(dayOf(moved.startsAt.toLocal()), target);
    expect(moved.startsAt.toLocal().hour, 10);
    expect(moved.endsAt.difference(moved.startsAt), const Duration(hours: 2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
