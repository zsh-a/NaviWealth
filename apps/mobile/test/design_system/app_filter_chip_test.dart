import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: FScaffold(childPad: false, child: Center(child: child)),
    ),
  );
}

void main() {
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
        ),
      ),
    );

    await tester.tap(find.text('Meals'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(pressed, isTrue);

    await tester.tap(find.byIcon(FLucideIcons.x));
    await tester.pump(const Duration(milliseconds: 120));
    expect(cleared, isTrue);
  });
}
