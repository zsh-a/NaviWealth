import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets(
    'a shrinking scrolled list restores its header without rebuilding during layout',
    (tester) async {
      final count = ValueNotifier(100);
      final scroll = ScrollController();
      addTearDown(count.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: DomainTabScaffold(
              title: 'Health',
              child: ValueListenableBuilder<int>(
                valueListenable: count,
                builder: (_, value, _) => ListView.builder(
                  controller: scroll,
                  itemCount: value,
                  itemExtent: 80,
                  itemBuilder: (_, index) => Text('Record $index'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      expect(find.text('Health'), findsNothing);
      count.value = 1;
      await tester.pumpAndSettle();
      expect(find.text('Health'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
