import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap({
  AppSurfaceStyle style = AppSurfaceStyle.standard,
  Brightness brightness = Brightness.light,
  bool platformHighContrast = false,
}) {
  final appTheme = brightness == Brightness.dark
      ? AppTheme.dark(surfaceStyle: style)
      : AppTheme.light(surfaceStyle: style);
  final resolved = resolveAppTheme(
    ThemeInputs(
      brightness: brightness,
      marketMode: MarketColorMode.redUpGreenDown,
      surfaceStyle: style,
    ),
  );
  return MaterialApp(
    theme: appTheme,
    home: FTheme(
      data: buildAppForuiTheme(
        brightness: brightness,
        touch: true,
        surfaceStyle: style,
      ),
      child: AppThemeScope(
        data: resolved,
        child: MediaQuery(
          data: MediaQueryData(highContrast: platformHighContrast),
          child: const Scaffold(body: AppGlassSurface(child: Text('glass'))),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('standard surface uses one live backdrop layer', (tester) async {
    await tester.pumpWidget(_wrap());

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('high-contrast theme replaces blur with opaque material', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(style: AppSurfaceStyle.highContrast));

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('OLED theme preserves the black canvas without live blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(style: AppSurfaceStyle.oled, brightness: Brightness.dark),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('platform high contrast overrides the standard glass style', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(platformHighContrast: true));

    expect(find.byType(BackdropFilter), findsNothing);
  });
}
