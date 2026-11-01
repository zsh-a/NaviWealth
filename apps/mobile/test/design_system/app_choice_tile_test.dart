import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) => AppThemeScope(
  data: resolveAppTheme(
    const ThemeInputs(
      brightness: Brightness.light,
      marketMode: MarketColorMode.redUpGreenDown,
    ),
  ),
  child: MaterialApp(
    home: FTheme(
      data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
      child: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'choice tiles support keyboard selection and disabled semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var selected = 'Bank';
      final changes = <String>[];
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in ['Bank', 'Cash', 'Unavailable'])
                  AppChoiceTile(
                    selected: selected == value,
                    onPress: value == 'Unavailable'
                        ? null
                        : () {
                            changes.add(value);
                            setState(() => selected = value);
                          },
                    child: Text(value),
                  ),
              ],
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(changes, ['Cash']);
      expect(
        tester.getSemantics(find.text('Cash')).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(find.text('Bank')).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      for (final tile in tester.widgetList<AppChoiceTile>(
        find.byType(AppChoiceTile),
      )) {
        expect(
          tester.getSize(find.byWidget(tile)).height,
          greaterThanOrEqualTo(48),
        );
      }
      final disabled = tester.getSemantics(find.text('Unavailable'));
      expect(
        disabled.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      await tester.tap(find.text('Unavailable'));
      await tester.pumpAndSettle();
      expect(changes, ['Cash']);
      semantics.dispose();
    },
  );

  testWidgets('nested profile actions remain available on the active choice', (
    tester,
  ) async {
    var edits = 0;
    await tester.pumpWidget(
      _wrap(
        AppChoiceTile(
          selected: true,
          onPress: null,
          child: Row(
            children: [
              const Expanded(child: Text('Active profile')),
              AppIconButton(
                icon: FLucideIcons.pencil,
                tooltip: 'Edit profile',
                onPress: () => edits++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();
    expect(edits, 1);
  });
}
