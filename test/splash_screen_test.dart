import 'package:avidus_product/features/app/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('splash shows the BldTrack mark', (tester) async {
    final progress = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 1),
    );
    addTearDown(progress.dispose);
    progress.value = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: BldTrackSplashView(progress: progress),
      ),
    );

    expect(find.text('BldTrack'), findsOneWidget);
    expect(find.text('Build smarter'), findsOneWidget);
    expect(find.byIcon(Icons.apartment_rounded), findsOneWidget);
  });
}
