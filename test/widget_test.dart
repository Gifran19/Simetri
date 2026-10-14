import 'package:flutter_test/flutter_test.dart';
import 'package:my_test_app/main.dart';

void main() {
  testWidgets('App smoke test - verifies WelcomeScreen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const SimentriApp());
    expect(find.text('Get Started'), findsOneWidget);
  });
}
