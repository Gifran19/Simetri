import 'package:flutter_test/flutter_test.dart';
import 'package:my_test_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App smoke test - verifies WelcomeScreen loads', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'simetri_has_onboarded': false});
    await tester.pumpWidget(const SimentriApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Get Started'), findsOneWidget);
  });
}
