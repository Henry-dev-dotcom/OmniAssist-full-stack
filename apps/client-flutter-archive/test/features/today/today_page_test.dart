import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/app/providers.dart';
import 'package:omniassist/core/time/app_clock.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/auth/auth_controller.dart';
import 'package:omniassist/features/auth/auth_repository.dart';
import 'package:omniassist/features/sync/sync_controller.dart';
import 'package:omniassist/features/today/today_page.dart';

class _SignedIn extends AuthController {
  @override
  Future<Session?> build() async =>
      const Session(userId: 'u1', workspaceId: 'w1');
}

class _IdleSync extends SyncController {
  @override
  SyncUiState build() => const SyncUiState();
}

Future<AppDatabase> _pump(WidgetTester tester, {double textScale = 1}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 10, 15, 10))),
        authControllerProvider.overrideWith(_SignedIn.new),
        syncControllerProvider.overrideWith(_IdleSync.new),
      ],
      child: const MaterialApp(home: TodayPage()),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

/// Drift closes stream queries on a zero-length timer; let it fire before the test ends.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

void main() {
  testWidgets('empty Today offers creation actions and works offline', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('A clear day'), findsOneWidget);
    for (final label in [
      'Capture a task',
      'Plan a time block',
      'Start a project',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // No network anywhere in this test: Today reads only the local database.
    expect(find.text('Saved on this device'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a captured task shows as a priority with labelled actions', (
    tester,
  ) async {
    final db = await _pump(tester);
    // Real async for database writes; widget tests otherwise run in fake time.
    await tester.runAsync(
      () => db.taskDao.createWithOutbox(
        id: 't1',
        workspaceId: 'w1',
        title: 'Submit abstract',
        mutationId: 'm1',
        now: DateTime.utc(2026, 10, 15),
      ),
    );
    await tester.runAsync(
      () => db.taskDao.updateWithOutbox(
        id: 't1',
        changes: {'priority': 'high'},
        mutationId: 'm2',
        now: DateTime.utc(2026, 10, 15),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Top priorities'), findsOneWidget);
    expect(find.text('Submit abstract'), findsOneWidget);
    expect(find.bySemanticsLabel('Mark Submit abstract done'), findsOneWidget);
    expect(find.byTooltip('More actions for Submit abstract'), findsOneWidget);
    expect(find.text('2 changes waiting to sync'), findsOneWidget);

    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Top priorities')),
      isSemantics(label: 'Top priorities', isHeader: true),
    );
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('200% text still lays out on a phone (WCAG text scaling)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, textScale: 2);
    expect(tester.takeException(), isNull); // no overflow errors
    expect(find.text('Capture a task'), findsOneWidget);
    await _unmount(tester);
  });
}
