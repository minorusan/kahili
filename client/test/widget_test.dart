import 'package:flutter_test/flutter_test.dart';
import 'package:kahili_web/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const KahiliApp());
    expect(find.text('Kahili'), findsOneWidget);
  });
}
