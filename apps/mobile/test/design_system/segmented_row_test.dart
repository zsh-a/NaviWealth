import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {double width = 400}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: FScaffold(
        childPad: false,
        child: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders one labelled segment per option', (tester) async {
    String? changedTo;
    await tester.pumpWidget(
      _wrap(
        SegmentedRow<String>(
          options: const ['a', 'b', 'c'],
          value: 'a',
          labelOf: (s) => s.toUpperCase(),
          onChanged: (value) => changedTo = value,
        ),
      ),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);

    await tester.tap(find.text('B'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(changedTo, 'b');
  });

  testWidgets('long labels in the equal-split layout do not overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        // Two wide labels at 400dp force each Expanded slot narrower than
        // the label's intrinsic width — the exact case that overflowed
        // the hand-rolled wealth toggle before consolidation.
        SegmentedRow<int>(
          options: const [0, 1],
          value: 0,
          labelOf: (i) => i == 0 ? 'By category' : 'By currency',
          onChanged: (_) {},
        ),
      ),
    );
    // No RenderFlex overflow exception is thrown during layout.
    expect(tester.takeException(), isNull);
    expect(find.text('By category'), findsOneWidget);
  });

  testWidgets('falls back to a horizontal scroll on narrow widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        // 5 segments / 200dp → each slot < 96dp min → scroll fallback.
        SegmentedRow<int>(
          options: const [0, 1, 2, 3, 4],
          value: 2,
          labelOf: (i) => 'Segment $i',
          onChanged: (_) {},
        ),
        width: 200,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
