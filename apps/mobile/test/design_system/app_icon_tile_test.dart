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
  testWidgets('renders the configured icon', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AppIconTile(
          icon: FLucideIcons.activity,
          color: ColorPalette.cyanBrand500,
        ),
      ),
    );

    expect(find.byIcon(FLucideIcons.activity), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
