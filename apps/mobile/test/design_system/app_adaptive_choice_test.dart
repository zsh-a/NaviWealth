import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {double width = 390}) {
  return MaterialApp(
    theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('uses one compact trigger for four mobile choices', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => AppAdaptiveChoice<int>(
            title: 'Choose scope',
            options: const [0, 1, 2, 3],
            value: selected,
            labelOf: (value) => 'Scope $value',
            descriptionOf: (value) => 'Description $value',
            iconOf: (_) => Icons.layers_outlined,
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );

    expect(find.text('Scope 0'), findsOneWidget);
    expect(find.byType(SegmentedRow<int>), findsNothing);

    await tester.tap(find.text('Scope 0'));
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.text('Description 3'), findsOneWidget);

    await tester.tap(find.text('Scope 3'));
    await tester.pumpAndSettle();
    expect(selected, 3);
    expect(find.text('Scope 3'), findsOneWidget);
  });

  testWidgets('keeps three choices inline and returns four inline when wide', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppAdaptiveChoice<int>(
          title: 'Choose scope',
          options: const [0, 1, 2],
          value: 0,
          labelOf: (value) => 'Scope $value',
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.byType(SegmentedRow<int>), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        AppAdaptiveChoice<int>(
          title: 'Choose scope',
          options: const [0, 1, 2, 3],
          value: 0,
          labelOf: (value) => 'Scope $value',
          wideInlineBreakpoint: 720,
          onChanged: (_) {},
        ),
        width: 1000,
      ),
    );
    expect(find.byType(SegmentedRow<int>), findsOneWidget);
  });
}
