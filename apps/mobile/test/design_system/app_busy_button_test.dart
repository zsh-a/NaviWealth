import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
      data: buildAppForuiTheme(brightness: Brightness.light, touch: false),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('long labels wrap at large text instead of shrinking', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SizedBox(
            width: 220,
            child: AppBusyButton(
              label: 'Save all account changes',
              busyLabel: 'Saving all account changes',
              onPress: () {},
            ),
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Save all account changes'),
    );
    expect(paragraph.textScaler.scale(14), 28);
    expect(paragraph.size.height, greaterThan(28));
    expect(tester.takeException(), isNull);
  });

  testWidgets('content-width loading preserves geometry, label and fill', (
    tester,
  ) async {
    final busy = ValueNotifier(false);
    addTearDown(busy.dispose);
    const key = ValueKey('save-action');
    await tester.pumpWidget(
      _wrap(
        ValueListenableBuilder<bool>(
          valueListenable: busy,
          builder: (_, value, _) => AppBusyButton(
            buttonKey: key,
            label: 'Save',
            busyLabel: 'Saving changes',
            busy: value,
            mainAxisSize: MainAxisSize.min,
            onPress: () {},
          ),
        ),
      ),
    );
    final initialSize = tester.getSize(find.byKey(key));
    final initialLabel = tester.getCenter(find.text('Save').last);
    Color? fill() => tester
        .widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byKey(key),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        )
        .decoration
        ?.color;
    final initialFill = fill();
    busy.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(find.byKey(key)), initialSize);
    expect(tester.getCenter(find.text('Saving changes').last), initialLabel);
    expect(fill(), initialFill);
    expect(find.byType(FCircularProgress), findsOneWidget);
    busy.value = false;
    await tester.pumpAndSettle();
  });

  testWidgets('busy transition releases focus and blocks keyboard activation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final busy = ValueNotifier(false);
    addTearDown(busy.dispose);
    var presses = 0;
    var ancestorActivations = 0;
    await tester.pumpWidget(
      _wrap(
        Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => ancestorActivations++,
            ),
          },
          child: ValueListenableBuilder<bool>(
            valueListenable: busy,
            builder: (_, value, _) => AppBusyButton(
              label: 'Save',
              busyLabel: 'Saving',
              busy: value,
              onPress: () => presses++,
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(presses, 1);
    busy.value = true;
    await tester.pump();
    await tester.pump();
    final data = find.semantics
        .byLabel('Saving')
        .evaluate()
        .single
        .getSemanticsData();
    expect(data.flagsCollection.isFocused, isNot(ui.Tristate.isTrue));
    expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    Actions.invoke(
      tester.element(find.text('Saving').last),
      const ActivateIntent(),
    );
    expect(presses, 1);
    expect(ancestorActivations, 0);
    busy.value = false;
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('uses a stable label and invokes the idle action', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _wrap(
        AppBusyButton(
          label: 'Save',
          busyLabel: 'Saving',
          onPress: () => presses++,
        ),
      ),
    );

    expect(find.text('Save'), findsOneWidget);
    expect(find.byType(FCircularProgress), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(presses, 1);
  });

  testWidgets('shows progress and blocks activation while busy', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _wrap(
        AppBusyButton(
          label: 'Save',
          busyLabel: 'Saving',
          busy: true,
          onPress: () => presses++,
        ),
      ),
    );

    expect(find.text('Saving'), findsOneWidget);
    expect(find.byType(FCircularProgress), findsOneWidget);
    await tester.tap(find.text('Saving'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(presses, 0);
  });

  group('haptics', () {
    final hapticCalls = <String>[];

    setUp(() {
      hapticCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              hapticCalls.add((call.arguments as String?) ?? 'default');
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    /// Enables haptics for the duration of [body]; the platform override is a
    /// foundation debug variable that must be restored before the widget-test
    /// invariant check, so it cannot live in `tearDown`.
    Future<void> withHaptics(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('fires commit feedback on press by default', (tester) async {
      await withHaptics(() async {
        await tester.pumpWidget(
          _wrap(AppBusyButton(label: 'Save', onPress: () {})),
        );

        await tester.tap(find.text('Save'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(hapticCalls, ['HapticFeedbackType.lightImpact']);
      });
    });

    testWidgets('stays silent when hapticIntent is null', (tester) async {
      await withHaptics(() async {
        var presses = 0;
        await tester.pumpWidget(
          _wrap(
            AppBusyButton(
              label: 'Save',
              onPress: () => presses++,
              hapticIntent: null,
            ),
          ),
        );

        await tester.tap(find.text('Save'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(presses, 1);
        expect(hapticCalls, isEmpty);
      });
    });

    testWidgets('does not fire while busy', (tester) async {
      await withHaptics(() async {
        await tester.pumpWidget(
          _wrap(
            AppBusyButton(
              label: 'Save',
              busyLabel: 'Saving',
              busy: true,
              onPress: () {},
            ),
          ),
        );

        await tester.tap(find.text('Saving'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(hapticCalls, isEmpty);
      });
    });
  });
}
