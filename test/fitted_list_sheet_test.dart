import 'package:avidus_product/features/pms/widgets/pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openSheet(WidgetTester tester, {required int count}) async {
  tester.view.viewPadding = const FakeViewPadding(top: 48);
  tester.view.padding = const FakeViewPadding(top: 48);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => FittedListSheet(
                    title: 'Filter by site',
                    topInset: 48,
                    onClose: () => Navigator.pop(context),
                    itemCount: count,
                    itemBuilder: (_, i) => ListTile(title: Text('Site $i')),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('short filter list ends at the last item', (tester) async {
    await _openSheet(tester, count: 3);
    final sheet = tester.getRect(find.byType(FittedListSheet));
    final last = tester.getRect(find.widgetWithText(ListTile, 'Site 2'));
    expect(sheet.bottom - last.bottom, lessThan(2));
    expect(find.text('Site 0'), findsOneWidget);
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isFalse);
  });

  testWidgets('long filter list caps height and shows a scrollbar', (tester) async {
    await _openSheet(tester, count: 40);
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final sheet = tester.getSize(find.byType(FittedListSheet));
    expect(sheet.height, greaterThan(screen * 0.7));
    expect(sheet.height, lessThanOrEqualTo(screen * 0.75 + 1));
    expect(find.text('Site 0'), findsOneWidget);
    expect(find.text('Site 39'), findsNothing);
    expect(tester.getRect(find.byTooltip('Close')).top, greaterThanOrEqualTo(48));
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
  });
}
