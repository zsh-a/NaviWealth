import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets('builds repeated rows lazily near the viewport', (tester) async {
    var built = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: BriefLazyListScaffold(
              atmosphere: false,
              greeting: const SizedBox(height: 20),
              stage: const SizedBox(height: 80),
              itemCount: 1000,
              itemBuilder: (context, index) {
                built += 1;
                return SizedBox(height: 80, child: Text('row-$index'));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('row-0'), findsOneWidget);
    expect(built, lessThan(20));
    expect(find.text('row-999'), findsNothing);
  });
}
