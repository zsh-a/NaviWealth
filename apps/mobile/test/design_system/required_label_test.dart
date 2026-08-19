import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: FScaffold(
        childPad: false,
        child: Center(child: SizedBox(width: 180, child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('required marker wraps with a long large-text label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: RequiredLabel('A deliberately long required field label'),
        ),
      ),
    );

    expect(
      find.text('A deliberately long required field label *'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
