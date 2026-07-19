import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _themed({required bool touch, required Widget child}) {
  return MaterialApp(
    home: FTheme(
      data: buildAppForuiTheme(brightness: Brightness.light, touch: touch),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  for (final touch in <bool>[false, true]) {
    testWidgets('actions use ${touch ? 'touch' : 'desktop'} target size', (
      tester,
    ) async {
      const buttonKey = ValueKey('action-button');
      const headerKey = ValueKey('header-action');
      final expected = touch ? 48.0 : 40.0;

      await tester.pumpWidget(
        _themed(
          touch: touch,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FHeader(
                title: const Text('Header'),
                suffixes: [
                  AppHeaderAction(
                    key: headerKey,
                    semanticsLabel: 'Refresh',
                    icon: const Icon(FLucideIcons.refreshCw),
                    onPress: () {},
                  ),
                ],
              ),
              AppActionButton(
                key: buttonKey,
                mainAxisSize: MainAxisSize.min,
                onPress: () {},
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      );

      expect(tester.getSize(find.byKey(buttonKey)).height, expected);
      expect(tester.getSize(find.byKey(headerKey)), Size.square(expected));
    });
  }

  testWidgets('header action exposes one named button and hides its icon', (
    tester,
  ) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _themed(
        touch: true,
        child: FHeader(
          suffixes: [
            AppHeaderAction(
              semanticsLabel: 'Import file',
              icon: const Icon(
                FLucideIcons.paperclip,
                semanticLabel: 'Decorative paperclip',
              ),
              onPress: () => taps += 1,
            ),
          ],
        ),
      ),
    );

    final actionFinder = find.semantics.byLabel('Import file');
    final node = actionFinder.evaluate().single;
    final data = node.getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(find.semantics.byLabel('Decorative paperclip').evaluate(), isEmpty);

    tester.semantics.tap(actionFinder);
    await tester.pump();
    expect(taps, 1);

    final target = tester.getRect(find.byType(AppHeaderAction));
    await tester.tapAt(target.topLeft + const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(taps, 2);
    semantics.dispose();
  });

  testWidgets('header action owns its contextual tooltip', (tester) async {
    await tester.pumpWidget(
      _themed(
        touch: false,
        child: const FHeader(
          suffixes: [
            AppHeaderAction(
              semanticsLabel: 'Refresh data',
              icon: Icon(FLucideIcons.refreshCw),
              onPress: null,
            ),
          ],
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(AppHeaderAction),
        matching: find.byType(FTooltip),
      ),
      findsOneWidget,
    );
  });

  testWidgets('text action exposes one natural-label button', (tester) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _themed(
        touch: true,
        child: AppActionButton(
          onPress: () => taps += 1,
          child: const Text('Continue'),
        ),
      ),
    );

    final buttonFinder = find.semantics.byLabel('Continue');
    final node = buttonFinder.evaluate().single.getSemanticsData();
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(node.hasAction(SemanticsAction.tap), isTrue);

    tester.semantics.tap(buttonFinder);
    await tester.pump();
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets(
    'header keyboard activation is repeat-safe and disabled locally',
    (tester) async {
      final enabled = ValueNotifier(true);
      final headerFocus = FocusNode(debugLabel: 'header-action');
      final nextFocus = FocusNode(debugLabel: 'next-action');
      addTearDown(() {
        enabled.dispose();
        headerFocus.dispose();
        nextFocus.dispose();
      });
      var taps = 0;
      var ancestorActivations = 0;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _themed(
          touch: true,
          child: Actions(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  ancestorActivations += 1;
                  return null;
                },
              ),
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: enabled,
              builder: (context, isEnabled, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FHeader(
                    title: const Text('Header'),
                    suffixes: [
                      AppHeaderAction(
                        semanticsLabel: 'Archive',
                        icon: const Icon(FLucideIcons.archive),
                        focusNode: headerFocus,
                        onPress: isEnabled ? () => taps += 1 : null,
                      ),
                    ],
                  ),
                  TextButton(
                    focusNode: nextFocus,
                    onPressed: () {},
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(headerFocus.hasFocus, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      expect(taps, 1);
      expect(ancestorActivations, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(taps, 2);
      expect(ancestorActivations, 0);

      enabled.value = false;
      await tester.pump();
      expect(headerFocus.hasFocus, isFalse);

      final disabledFinder = find.semantics.byLabel('Archive');
      final disabledData = disabledFinder.evaluate().single.getSemanticsData();
      expect(disabledData.flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(disabledData.hasAction(SemanticsAction.tap), isFalse);

      final headerContext = tester.element(find.byIcon(FLucideIcons.archive));
      Actions.invoke(headerContext, const ActivateIntent());
      expect(taps, 2);
      expect(ancestorActivations, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(nextFocus.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      semantics.dispose();
    },
  );

  testWidgets(
    'keyboard repeats once, disabling unfocuses and blocks ancestor action',
    (tester) async {
      final enabled = ValueNotifier(true);
      final buttonFocus = FocusNode(debugLabel: 'primary-action');
      final nextFocus = FocusNode(debugLabel: 'next-action');
      addTearDown(() {
        enabled.dispose();
        buttonFocus.dispose();
        nextFocus.dispose();
      });
      var taps = 0;
      var ancestorActivations = 0;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _themed(
          touch: false,
          child: Actions(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  ancestorActivations += 1;
                  return null;
                },
              ),
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: enabled,
              builder: (context, isEnabled, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppActionButton(
                    focusNode: buttonFocus,
                    mainAxisSize: MainAxisSize.min,
                    onPress: isEnabled ? () => taps += 1 : null,
                    child: const Text('Run action'),
                  ),
                  TextButton(
                    focusNode: nextFocus,
                    onPressed: () {},
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(buttonFocus.hasFocus, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      expect(taps, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(taps, 2);
      expect(ancestorActivations, 0);

      enabled.value = false;
      await tester.pump();
      expect(buttonFocus.hasFocus, isFalse);

      final disabledFinder = find.semantics.byLabel('Run action');
      final disabledData = disabledFinder.evaluate().single.getSemanticsData();
      expect(disabledData.flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(disabledData.hasAction(SemanticsAction.tap), isFalse);

      final buttonContext = tester.element(find.text('Run action'));
      Actions.invoke(buttonContext, const ActivateIntent());
      expect(taps, 2);
      expect(ancestorActivations, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(nextFocus.hasFocus, isTrue);
      semantics.dispose();
    },
  );
}
