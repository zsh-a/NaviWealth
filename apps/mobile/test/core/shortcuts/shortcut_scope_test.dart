import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/shortcuts/shortcut_scope.dart';

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
  testWidgets('ShortcutScope fires bound callbacks on key press', (
    tester,
  ) async {
    await _runOnDesktop(() async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ShortcutScope(
            autofocus: true,
            shortcuts: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
                  calls++,
              const SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
              ): () =>
                  calls++,
            },
            child: const Scaffold(
              body: Focus(autofocus: true, child: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(calls, 1);
    });
  });

  testWidgets('ShortcutScope is a passthrough on mobile platforms', (
    tester,
  ) async {
    if (kIsWeb) return; // Web is always considered desktop-capable.
    await _runOnDesktop(platform: TargetPlatform.android, () async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ShortcutScope(
            autofocus: true,
            shortcuts: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyN): () => calls++,
            },
            child: const Scaffold(
              body: Focus(autofocus: true, child: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();

      expect(calls, 0);
    });
  });

  testWidgets('ShortcutScope skips when a TextField has focus', (tester) async {
    await _runOnDesktop(() async {
      var calls = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShortcutScope(
              shortcuts: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.keyN): () => calls++,
              },
              child: TextField(controller: controller, autofocus: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.focusManager.primaryFocus, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();

      expect(calls, 0);
    });
  });
}
