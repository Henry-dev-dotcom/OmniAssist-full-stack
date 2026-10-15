import 'package:flutter/material.dart';
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
  for (final path in ['/onboarding', '/app/search']) {
    testWidgets('route $path renders a placeholder', (tester) async {
      await tester.pumpWidget(_app(path));
      await tester.pumpAndSettle();
      expect(find.text('Coming in a later task.'), findsOneWidget);
    });
  }

  testWidgets('tapping Calendar navigates', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app('/app/search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Calendar'), findsWidgets);
  });
}
