import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets(
    'collapse fades before removal and outgoing content ignores taps',
    (tester) async {
      final expanded = ValueNotifier(true);
      addTearDown(expanded.dispose);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: ValueListenableBuilder<bool>(
                valueListenable: expanded,
                builder: (_, visible, _) => AnimatedSizeFade(
                  visible: visible,
                  child: GestureDetector(
                    onTap: () => taps++,
                    child: const SizedBox(
                      width: 200,
                      height: 120,
                      child: Text('Details'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Details'));
      expect(taps, 1);
      expanded.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Details'), findsOneWidget);
      final height = tester.getSize(find.byType(AnimatedSizeFade)).height;
      expect(height, greaterThan(0));
      expect(height, lessThan(120));
      await tester.tapAt(
        tester.getTopLeft(find.byType(AnimatedSizeFade)) + const Offset(10, 10),
      );
      expect(taps, 1);
      expanded.value = true;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      expect(tester.getSize(find.byType(AnimatedSizeFade)).height, 120);
      expanded.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsNothing);
    },
  );

  testWidgets('reduced motion uses a short fade without spatial reveal', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AnimatedSizeFade(visible: true, child: Text('Details')),
        ),
      ),
    );
    expect(find.byType(SizeTransition), findsNothing);
    expect(find.text('Details'), findsOneWidget);
  });
}
