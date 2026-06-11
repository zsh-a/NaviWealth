import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

/// Regression guard for the "keyboard obscures the sheet" bug.
///
/// Keyboard avoidance for app sheets is owned entirely by forui's modal
/// sheet (`showFSheet(resizeToAvoidBottomInset: true)`), which translates
/// the whole min-sized sheet — footer included — above the keyboard. If
/// the [AppSheet] footer branch *also* pads by `MediaQuery.viewInsets`,
/// the keyboard gets counted twice: the sheet inflates by the keyboard
/// height and is then lifted by the same amount, jamming the content to
/// the top with a keyboard-sized empty band above the keyboard.
Widget _wrap(Widget child, {required double keyboardInset}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: MediaQuery(
        data: MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('AppSheetSurface defaults to no blur and dedupes frosted blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        keyboardInset: 0,
        const AppSheetSurface(
          child: AppSheetSurface(
            child: SizedBox(key: Key('content'), height: 120),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('content')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pumpWidget(
      _wrap(
        keyboardInset: 0,
        const AppSheetSurface(
          frosted: true,
          child: AppSheetSurface(
            frosted: true,
            child: SizedBox(key: Key('content'), height: 120),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets(
    'AppSheet footer branch does not self-pad by the keyboard inset',
    (tester) async {
      const keyboardInset = 300.0;
      await tester.pumpWidget(
        _wrap(
          keyboardInset: keyboardInset,
          const AppSheet(
            title: 'Paste',
            footer: SizedBox(key: Key('footer'), height: 48),
            child: SizedBox(key: Key('body'), height: 120),
          ),
        ),
      );

      expect(find.byKey(const Key('body')), findsOneWidget);
      expect(find.byKey(const Key('footer')), findsOneWidget);

      // No Padding inside the sheet may reserve the keyboard height —
      // that double-counts forui's own keyboard lift.
      final paddings = tester.widgetList<Padding>(
        find.descendant(
          of: find.byType(AppSheet),
          matching: find.byType(Padding),
        ),
      );
      for (final p in paddings) {
        final pad = p.padding.resolve(TextDirection.ltr);
        expect(
          pad.bottom,
          isNot(keyboardInset),
          reason:
              'AppSheet must not pad by viewInsets.bottom; forui already '
              'lifts the sheet above the keyboard.',
        );
      }
    },
  );
}
