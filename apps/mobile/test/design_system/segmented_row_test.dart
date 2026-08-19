import 'dart:ui' show Tristate;

import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {double width = 400, double textScale = 1}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: FTheme(
        data: FTheme.neutral.light.desktop,
        child: FScaffold(
          childPad: false,
          child: Center(
            child: SizedBox(width: width, child: child),
          ),
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

  testWidgets('wraps all options on narrow widths', (tester) async {
    await tester.pumpWidget(
      _wrap(
        // 5 segments / 200dp → each slot < 96dp min → visible wrap fallback.
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
    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('balances four wrapped options into two columns', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SegmentedRow<int>(
          options: const [0, 1, 2, 3],
          value: 0,
          labelOf: (i) => 'Option $i',
          onChanged: (_) {},
        ),
        width: 320,
      ),
    );

    final option = tester.getSize(find.text('Option 0'));
    final nextRow = tester.getTopLeft(find.text('Option 2'));
    final firstRow = tester.getTopLeft(find.text('Option 0'));
    expect(option.width, greaterThan(0));
    expect(nextRow.dy, greaterThan(firstRow.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text switches equal segments to visible wrapping', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SegmentedRow<int>(
          options: const [0, 1, 2],
          value: 0,
          labelOf: (i) => 'Option $i',
          onChanged: (_) {},
        ),
        textScale: 2,
      ),
    );

    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('separates compact labels from full selected semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(
        SegmentedRow<String>(
          options: const ['alpha', 'beta'],
          value: 'alpha',
          labelOf: (value) => value == 'alpha' ? 'A' : 'B',
          semanticLabelOf: (value) => 'Full $value',
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.bySemanticsLabel('Full alpha'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Full alpha'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Full beta'))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Full beta'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('segments activate from Enter and Space', (tester) async {
    String? changedTo;
    await tester.pumpWidget(
      _wrap(
        SegmentedRow<String>(
          options: const ['a', 'b'],
          value: 'a',
          labelOf: (value) => value.toUpperCase(),
          onChanged: (value) => changedTo = value,
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    // Activating the already-selected segment is intentionally a no-op.
    expect(changedTo, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(changedTo, 'b');
  });
}
