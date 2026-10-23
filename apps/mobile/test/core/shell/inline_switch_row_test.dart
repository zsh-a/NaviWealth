import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/shell/settings_ui/inline_setting_row.dart';
import 'package:naviwealth/design_system/design_system.dart';

Future<void> pumpRow(
  WidgetTester tester, {
  bool enabled = true,
  ValueChanged<bool>? onChanged,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: FTheme(
        data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
        child: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: textScaler),
            child: Center(
              child: SizedBox(
                width: 360,
                child: InlineSwitchRow(
                  icon: FLucideIcons.listTodo,
                  label: 'ExecutionOS',
                  subtitle: 'Turn decisions into actions.',
                  value: false,
                  enabled: enabled,
                  onChanged: onChanged ?? (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('exposes one named switch with its description and state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpRow(tester);
    final finder = find.bySemanticsLabel('ExecutionOS');
    expect(finder, findsOneWidget);
    final data = tester.getSemantics(finder).getSemanticsData();
    expect(data.hint, 'Turn decisions into actions.');
    expect(data.flagsCollection.isToggled, Tristate.isFalse);
    expect(data.flagsCollection.isEnabled, Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('label, padding and switch each toggle once', (tester) async {
    final changes = <bool>[];
    await pumpRow(tester, onChanged: changes.add);
    await tester.tap(find.text('ExecutionOS'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    await tester.tapAt(
      tester.getTopLeft(find.byType(InlineSwitchRow)) + const Offset(4, 4),
    );
    await tester.pumpAndSettle();
    expect(changes, [true, true]);
    await tester.tap(find.byType(FSwitch));
    await tester.pumpAndSettle();
    expect(changes, [true, true, true]);
  });

  testWidgets('keyboard users can focus and activate the row', (tester) async {
    final changes = <bool>[];
    await pumpRow(tester, onChanged: changes.add);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, [true]);
  });

  testWidgets('disabled row is announced and cannot be activated', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final changes = <bool>[];
    await pumpRow(tester, enabled: false, onChanged: changes.add);
    final data = tester
        .getSemantics(find.bySemanticsLabel('ExecutionOS'))
        .getSemanticsData();
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    await tester.tap(find.text('ExecutionOS'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(changes, isEmpty);
    semantics.dispose();
  });

  testWidgets('large text preserves the setting label and explanation', (
    tester,
  ) async {
    await pumpRow(tester, textScaler: const TextScaler.linear(2));
    expect(tester.takeException(), isNull);
    for (final label in ['ExecutionOS', 'Turn decisions into actions.']) {
      expect(tester.widget<Text>(find.text(label)).maxLines, isNull);
    }
  });
}
