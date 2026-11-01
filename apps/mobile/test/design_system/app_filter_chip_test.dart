import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: FScaffold(childPad: false, child: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('summary labels preserve filters and only clear removes them', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final removed = <int>[];
    var cleared = 0;
    await tester.pumpWidget(
      _wrap(
        AppFilterSummary(
          labels: const ['Meals', 'Notes'],
          onRemove: removed.add,
          onClear: () => cleared++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Meals'));
    await tester.pump();
    expect(removed, isEmpty);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Meals'))
          .getSemanticsData()
          .flagsCollection
          .isButton,
      isFalse,
    );

    final clear = find.bySemanticsLabel('Clear filters: Notes');
    final node = tester.getSemantics(clear);
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    expect(removed, [1]);
    expect(cleared, 0);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(cleared, 1);
    semantics.dispose();
  });

  testWidgets(
    'keyboard and semantic actions keep selection and clear distinct',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var presses = 0;
      var clears = 0;
      await tester.pumpWidget(
        _wrap(
          AppFilterChip(
            label: 'Meals',
            active: true,
            onPress: () => presses++,
            onClear: () => clears++,
            clearSemanticLabel: 'Clear meals',
          ),
        ),
      );
      final choice = tester.getSemantics(find.bySemanticsLabel('Meals'));
      expect(
        choice.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
      );
      choice.owner!.performAction(choice.id, SemanticsAction.tap);
      await tester.pump();
      expect(presses, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(presses, 2);
      final clear = tester.getSemantics(find.bySemanticsLabel('Clear meals'));
      clear.owner!.performAction(clear.id, SemanticsAction.tap);
      await tester.pump();
      expect(clears, 1);
      expect(presses, 2);
      semantics.dispose();
    },
  );

  testWidgets('invokes press and clear actions', (tester) async {
    var pressed = false;
    var cleared = false;
    await tester.pumpWidget(
      _wrap(
        AppFilterChip(
          label: 'Meals',
          active: true,
          onPress: () => pressed = true,
          onClear: () => cleared = true,
          clearSemanticLabel: 'Clear meals',
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(AppFilterChip)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'Clear meals',
        ),
      ),
      const Size(48, 48),
    );

    await tester.tap(find.text('Meals'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(pressed, isTrue);

    await tester.tap(find.byIcon(FLucideIcons.x));
    await tester.pump(const Duration(milliseconds: 120));
    expect(cleared, isTrue);
  });

  testWidgets('does not advertise a non-interactive chip as a button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AppFilterChip(
          label: 'Search: groceries',
          active: true,
          onPress: null,
        ),
      ),
    );

    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true,
      ),
    );
    expect(semantics.properties.button, isFalse);
  });
}
