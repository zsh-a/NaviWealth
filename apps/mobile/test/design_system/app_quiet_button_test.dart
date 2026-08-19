import 'package:flutter/material.dart';
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
