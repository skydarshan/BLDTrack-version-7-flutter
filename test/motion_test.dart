import 'package:avidus_product/core/widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('entrance keeps layout size and finishes visible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StaggeredEntrance(
              maxIndex: 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EntranceItem(
                    index: 0,
                    child: SizedBox(key: Key('card-a'), width: 120, height: 48),
                  ),
                  EntranceItem(
                    index: 1,
                    child: SizedBox(key: Key('card-b'), width: 120, height: 40),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('card-a'))), const Size(120, 48));
    expect(tester.getSize(find.byKey(const Key('card-b'))), const Size(120, 40));
    expect(tester.getSize(find.byType(Column)).height, 88);

    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(find.byKey(const Key('card-a'))), const Size(120, 48));
    expect(tester.getSize(find.byType(Column)).height, 88);

    await tester.pumpAndSettle();
    final fade = tester.widget<FadeTransition>(find.byType(FadeTransition).first);
    expect(fade.opacity.value, 1);
    expect(tester.getSize(find.byType(Column)).height, 88);
  });

  testWidgets('reduced motion shows content without an entrance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          );
        },
        home: const Scaffold(
          body: StaggeredEntrance(
            child: EntranceItem(index: 0, child: Text('Ready')),
          ),
        ),
      ),
    );

    expect(find.text('Ready'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(EntranceItem),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('press scale does not change layout size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PressScale(
            child: SizedBox(key: Key('button'), width: 80, height: 36),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('button'))), const Size(80, 36));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('button'))));
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getSize(find.byKey(const Key('button'))), const Size(80, 36));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('button'))), const Size(80, 36));
  });
}
