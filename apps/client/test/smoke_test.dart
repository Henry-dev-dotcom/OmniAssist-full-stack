import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/app/app.dart';

void main() {
  testWidgets('shell renders Today', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: OmniAssistApp()));
    await tester.pump(const Duration(seconds: 1)); // auth-restore spinner never settles
    expect(find.text('Today'), findsWidgets);
  });
}
