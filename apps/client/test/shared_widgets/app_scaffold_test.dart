import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/shared_widgets/app_scaffold.dart';

Future<void> _pump(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    const MaterialApp(
      home: AppScaffold(location: '/app/today', child: SizedBox()),
    ),
  );
}

void main() {
  testWidgets('desktop width uses a navigation rail', (tester) async {
    await _pump(tester, const Size(1200, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('mobile width uses a bottom bar', (tester) async {
    await _pump(tester, const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('primary navigation has a semantic label', (tester) async {
    await _pump(tester, const Size(1200, 800));
    expect(find.bySemanticsLabel('Primary navigation'), findsOneWidget);
  });
}
