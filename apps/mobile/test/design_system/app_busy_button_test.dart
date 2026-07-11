import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
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
}
