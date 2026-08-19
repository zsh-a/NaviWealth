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
  testWidgets('renders value, label, and icon', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AppInfoChip(
          icon: FLucideIcons.heartPulse,
          value: '42 ms',
          label: 'HRV',
          color: Color(0xFF0891B2),
        ),
      ),
    );

    expect(find.text('42 ms'), findsOneWidget);
    expect(find.text('HRV'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.heartPulse), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
