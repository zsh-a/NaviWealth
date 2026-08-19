import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/design_system/widgets/app_form_scaffold_body.dart';

/// Regression for the "keyboard pushes the form to the top, leaving a big
/// blank band in the middle" bug.
///
/// A form page builds its own `FScaffold(resizeToAvoidBottomInset: false)` +
/// [AppFormScaffoldBody] (which owns keyboard avoidance). When that page is
/// hosted inside the tab shell, the shell's own `FScaffold` must NOT also
/// resize for the keyboard — otherwise the inset is counted twice and the
/// action bar floats a keyboard-height above the keyboard.
///
/// This test reproduces the shell→form nesting and asserts the pinned action
/// bar sits within one nav-bar-height of the keyboard top (i.e. no
/// keyboard-sized blank band), so it fails on the double-count and passes once
/// the shell stops resizing.
void main() {
  const screen = Size(400, 800);
  const keyboard = 300.0;
  const actionKey = Key('form-action');

  Widget formPage() {
    // Mirrors every form page: own scaffold opts out of resize; the body owns
    // avoidance via AppFormScaffoldBody.
    return const FScaffold(
      childPad: false,
      resizeToAvoidBottomInset: false,
      child: AppFormScaffoldBody(
        action: SizedBox(key: actionKey, height: 48, width: double.infinity),
        children: [SizedBox(height: 1200)], // tall enough to scroll
      ),
    );
  }

  Future<void> pumpInShell(
    WidgetTester tester, {
    required bool shellResizes,
  }) async {
    tester.view.physicalSize = screen * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = screen;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FTheme(
        data: FTheme.neutral.light.desktop,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            // Simulate an open soft keyboard.
            data: const MediaQueryData(
              size: screen,
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: FScaffold(
              childPad: false,
              resizeToAvoidBottomInset: shellResizes,
              footer: const SizedBox(height: 56), // stand-in for the bottom nav
              child: formPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'shell that resizes double-counts the keyboard (repro of the blank band)',
    (tester) async {
      await pumpInShell(tester, shellResizes: true);

      final actionBottom = tester.getRect(find.byKey(actionKey)).bottom;
      final keyboardTop = screen.height - keyboard;
      // The double-count lifts the action bar a full keyboard height above the
      // keyboard — a large blank band.
      expect(keyboardTop - actionBottom, greaterThan(150));
    },
  );

  testWidgets(
    'shell that does not resize keeps the action bar just above the keyboard',
    (tester) async {
      await pumpInShell(tester, shellResizes: false);

      final actionBottom = tester.getRect(find.byKey(actionKey)).bottom;
      final keyboardTop = screen.height - keyboard;
      // Single owner of avoidance: the action bar sits above the keyboard with
      // only a small residual (the persistent bottom-nav band + the action
      // bar's own safe-area padding) — nowhere near the keyboard-sized blank
      // band the double-count produced (>150 above).
      expect(actionBottom, lessThanOrEqualTo(keyboardTop + 1));
      expect(keyboardTop - actionBottom, lessThan(120));
    },
  );
}
