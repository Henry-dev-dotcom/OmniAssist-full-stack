import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/app/providers.dart';
import 'package:omniassist/app/router.dart';
import 'package:omniassist/app/theme.dart';

Widget _app(String initial) => ProviderScope(
  overrides: [
    routerProvider.overrideWithValue(buildRouter(initialLocation: initial)),
  ],
  child: Consumer(
    builder: (_, ref, _) => MaterialApp.router(
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
    ),
  ),
);

void main() {
  testWidgets('tapping Calendar navigates', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app('/app/settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Calendar'), findsWidgets);
  });

  testWidgets('Alt+2 opens Calendar from the keyboard', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app('/app/settings'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('Not signed in'), findsOneWidget); // the Calendar screen
  });
}
