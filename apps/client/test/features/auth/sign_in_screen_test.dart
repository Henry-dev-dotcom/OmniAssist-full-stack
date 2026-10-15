import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/features/auth/sign_in_screen.dart';

void main() {
  testWidgets('toggle shows the name field and checks password length', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SignInScreen())),
    );
    expect(find.widgetWithText(TextField, 'Name'), findsNothing);

    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ada');
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.co');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(
      find.text('Use a password with at least 8 characters.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Have an account? Sign in'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Name'), findsNothing);
  });
}
