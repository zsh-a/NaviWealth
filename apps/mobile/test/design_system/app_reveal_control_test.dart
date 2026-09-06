import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: FScaffold(childPad: false, child: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('reveal control toggles via collapsed label', (tester) async {
    var expanded = false;
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => AppRevealControl(
            expanded: expanded,
            collapsedLabel: 'More · 3',
            expandedLabel: 'Show less',
            onToggle: () => setState(() => expanded = !expanded),
          ),
        ),
      ),
    );

    expect(find.text('More · 3'), findsOneWidget);
    await tester.tap(find.text('More · 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('disclosure header exposes title and toggles', (tester) async {
    var expanded = false;
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => AppDisclosureHeader(
            title: 'Sources',
            subtitle: 'Sync status',
            expanded: expanded,
            onToggle: () => setState(() => expanded = !expanded),
          ),
        ),
      ),
    );

    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Sync status'), findsOneWidget);
    await tester.tap(find.text('Sources'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(expanded, isTrue);
    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();
    expect(expanded, isFalse);
  });
}
