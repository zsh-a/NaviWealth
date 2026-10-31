import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

const _tabs = [
  FloatingNavTab(
    icon: FLucideIcons.house,
    selectedIcon: FLucideIcons.house,
    label: 'Today',
  ),
  FloatingNavTab(
    icon: FLucideIcons.wallet,
    selectedIcon: FLucideIcons.wallet,
    label: 'Wealth',
  ),
];

Widget _nav({
  required ValueChanged<int> onIndexChanged,
  required VoidCallback onAssistant,
  double width = 360,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: FTheme(
    data: buildAppForuiTheme(brightness: brightness, touch: false),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: FloatingGlassNavBar(
            items: _tabs,
            selectedIndex: 0,
            onIndexChanged: onIndexChanged,
            onAssistantAction: onAssistant,
            assistantLabel: 'Ask AI',
            assistantSemanticLabel: 'Open assistant conversation',
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final scale in [2.0, 3.0]) {
    testWidgets('enlarged navigation labels retain their scale at $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _nav(onIndexChanged: (_) {}, onAssistant: () {}, textScale: scale),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FloatingGlassNavBar)).height,
        greaterThan(kFloatingGlassNavBarHeight),
      );
      expect(
        MediaQuery.textScalerOf(tester.element(find.text('Today'))).scale(11),
        11 * scale,
      );
    });
  }

  for (final brightness in Brightness.values) {
    for (final width in [360.0, 500.0]) {
      testWidgets('one semantic control per destination: $brightness $width', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final selected = <int>[];
        var assistantTaps = 0;
        await tester.pumpWidget(
          _nav(
            brightness: brightness,
            width: width,
            onIndexChanged: selected.add,
            onAssistant: () => assistantTaps += 1,
          ),
        );

        final buttons = find.semantics.byPredicate(
          (node) => node.getSemanticsData().flagsCollection.isButton,
        );
        expect(buttons.evaluate(), hasLength(3));
        final today = find.semantics
            .byLabel('Today')
            .evaluate()
            .single
            .getSemanticsData();
        final wealth = find.semantics
            .byLabel('Wealth')
            .evaluate()
            .single
            .getSemanticsData();
        expect(today.flagsCollection.isSelected, ui.Tristate.isTrue);
        expect(wealth.flagsCollection.isSelected, ui.Tristate.isFalse);
        for (final button in buttons.evaluate()) {
          expect(
            button.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
        }
        expect(find.semantics.byLabel('Ask AI').evaluate(), isEmpty);

        tester.semantics.tap(find.semantics.byLabel('Wealth'));
        tester.semantics.tap(
          find.semantics.byLabel('Open assistant conversation'),
        );
        await tester.pumpAndSettle();
        expect(selected, [1]);
        expect(assistantTaps, 1);
        semantics.dispose();
      });
    }
  }

  testWidgets('Tab follows destinations and activation ignores key repeats', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final selected = <int>[];
    var assistantTaps = 0;
    await tester.pumpWidget(
      _nav(onIndexChanged: selected.add, onAssistant: () => assistantTaps += 1),
    );

    for (final label in ['Today', 'Wealth', 'Open assistant conversation']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final data = find.semantics
          .byLabel(label)
          .evaluate()
          .single
          .getSemanticsData();
      expect(data.flagsCollection.isFocused, ui.Tristate.isTrue);
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
      }
    }
    expect(selected, [0, 0, 1, 1]);
    expect(assistantTaps, 2);
    await tester.pumpAndSettle();
    semantics.dispose();
  });
}
