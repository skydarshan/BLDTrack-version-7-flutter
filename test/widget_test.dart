import 'package:flutter_test/flutter_test.dart';

import 'package:avidus_product/app.dart';

void main() {
  testWidgets('App boots to MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(const AvidusApp());
    await tester.pump();
    expect(find.byType(AvidusApp), findsOneWidget);
  });
}
