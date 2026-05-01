import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/shortcuts/global_shortcuts_scope.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

/// Runs [body] under a desktop platform override.
///
/// The framework's invariants check runs at the end of the test body — before
/// `tearDown` callbacks — so we restore [debugDefaultTargetPlatformOverride]
/// inside `finally` to keep tests hermetic.
Future<void> _runOnDesktop(
  Future<void> Function() body, {
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  group('GlobalShortcutsScope', () {
    testWidgets('digit key dispatches SwitchPrimaryTabIntent with the index', (
      tester,
    ) async {
      await _runOnDesktop(() async {
        final dispatched = <int>[];
        await tester.pumpWidget(
          _wrap(
            GlobalShortcutsScope(
              onSwitchPrimaryTab: dispatched.add,
              onOpenCommandPalette: (_) {},
              child: const Scaffold(
                body: Focus(autofocus: true, child: SizedBox()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
        await tester.pumpAndSettle();

        expect(dispatched, [1]);
      });
    });

    testWidgets('Cmd+K invokes the command palette callback', (tester) async {
      await _runOnDesktop(() async {
        var called = 0;
        await tester.pumpWidget(
          _wrap(
            GlobalShortcutsScope(
              onSwitchPrimaryTab: (_) {},
              onOpenCommandPalette: (_) => called++,
              child: const Scaffold(
                body: Focus(autofocus: true, child: SizedBox()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        expect(called, 1);
      });
    });

    testWidgets('digit keys are suppressed while a TextField has focus', (
      tester,
    ) async {
      await _runOnDesktop(() async {
        final dispatched = <int>[];
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _wrap(
            GlobalShortcutsScope(
              onSwitchPrimaryTab: dispatched.add,
              onOpenCommandPalette: (_) {},
              child: Scaffold(
                body: Center(
                  child: TextField(controller: controller, autofocus: true),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.binding.focusManager.primaryFocus, isNotNull);

        await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
        await tester.pumpAndSettle();

        expect(
          dispatched,
          isEmpty,
          reason: 'typing into a field must not switch app tabs',
        );
      });
    });

    testWidgets('Esc pops the topmost dialog', (tester) async {
      await _runOnDesktop(() async {
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GlobalShortcutsScope(
              onSwitchPrimaryTab: (_) {},
              onOpenCommandPalette: (_) {},
              child: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        unawaited(
          showDialog<void>(
            context: navigatorKey.currentContext!,
            builder: (_) => const AlertDialog(content: Text('hello')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('hello'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.text('hello'), findsNothing);
      });
    });
  });

  testWidgets('is a transparent passthrough on native mobile platforms', (
    tester,
  ) async {
    // kIsWeb is a compile-time constant so we can only assert the native
    // mobile branch here. On Web the scope is always active, which is
    // covered by the desktop tests above.
    if (kIsWeb) return;

    await _runOnDesktop(platform: TargetPlatform.iOS, () async {
      final dispatched = <int>[];
      await tester.pumpWidget(
        _wrap(
          GlobalShortcutsScope(
            onSwitchPrimaryTab: dispatched.add,
            onOpenCommandPalette: (_) {},
            child: const Scaffold(
              body: Focus(autofocus: true, child: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pumpAndSettle();

      expect(dispatched, isEmpty);
    });
  });
}
