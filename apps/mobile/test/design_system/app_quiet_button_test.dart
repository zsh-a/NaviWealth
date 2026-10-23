import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  testWidgets('exposes one full named button with a semantic tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    const label = 'Retry loading the complete activity history';

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 180,
          child: AppQuietButton(
            label: label,
            prefix: const Icon(Icons.refresh, semanticLabel: 'Decorative icon'),
            onPress: () => taps += 1,
          ),
        ),
      ),
    );

    final buttons = find.semantics.byPredicate(
      (node) => node.getSemanticsData().flagsCollection.isButton,
    );
    final data = buttons.evaluate().single.getSemanticsData();
    expect(data.label, label);
    expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(find.semantics.byLabel('Decorative icon').evaluate(), isEmpty);

    tester.semantics.tap(find.semantics.byLabel(label));
    await tester.pumpAndSettle();
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('busy state releases focus and blocks repeated activation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final busy = ValueNotifier(false);
    addTearDown(busy.dispose);
    var taps = 0;
    var ancestorActivations = 0;

    await tester.pumpWidget(
      _wrap(
        Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => ancestorActivations += 1,
            ),
          },
          child: ValueListenableBuilder<bool>(
            valueListenable: busy,
            builder: (context, value, _) => AppQuietButton(
              label: 'Retry',
              busyLabel: 'Retrying',
              busy: value,
              onPress: () => taps += 1,
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      find.semantics
          .byLabel('Retry')
          .evaluate()
          .single
          .getSemanticsData()
          .flagsCollection
          .isFocused,
      ui.Tristate.isTrue,
    );
    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
    }
    expect(taps, 2);
    expect(ancestorActivations, 0);

    busy.value = true;
    await tester.pump();
    await tester.pump();
    final data = find.semantics
        .byLabel('Retrying')
        .evaluate()
        .single
        .getSemanticsData();
    expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(data.flagsCollection.isFocused, isNot(ui.Tristate.isTrue));
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    Actions.invoke(
      tester.element(find.text('Retrying')),
      const ActivateIntent(),
    );
    expect(taps, 2);
    expect(ancestorActivations, 0);
    // End the busy animation before leaving the test.
    busy.value = false;
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets(
    'Android quiet actions retain a 48dp touch target at large text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: FTheme(
              data: FTheme.neutral.light.touch,
              child: Center(
                child: AppQuietButton(label: 'Retry', onPress: () {}),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(AppQuietButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('invokes the action when pressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      _wrap(AppQuietButton(label: 'Refresh', onPress: () => pressed = true)),
    );

    await tester.tap(find.text('Refresh'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(pressed, isTrue);
  });

  testWidgets('does not invoke the action while busy', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      _wrap(
        AppQuietButton(
          label: 'Refresh',
          busy: true,
          busyLabel: 'Refreshing',
          onPress: () => pressed = true,
        ),
      ),
    );

    expect(find.text('Refreshing'), findsOneWidget);
    await tester.tap(find.text('Refreshing'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 120));

    expect(pressed, isFalse);
  });
}
