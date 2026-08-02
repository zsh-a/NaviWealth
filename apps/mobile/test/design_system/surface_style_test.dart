import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

ThemeInputs _inputs(Brightness b, AppSurfaceStyle style) => ThemeInputs(
  brightness: b,
  marketMode: MarketColorMode.redUpGreenDown,
  surfaceStyle: style,
);

void main() {
  group('AppSurfaceStyle resolution', () {
    test('oled dark uses a true-black canvas and darker card ladder', () {
      final oled = resolveAppTheme(
        _inputs(Brightness.dark, AppSurfaceStyle.oled),
      );
      final standard = resolveAppTheme(
        _inputs(Brightness.dark, AppSurfaceStyle.standard),
      );
      expect(oled.surfaces.canvas, const Color(0xFF000000));
      expect(
        oled.surfaces.card.computeLuminance(),
        lessThan(standard.surfaces.card.computeLuminance()),
      );
      expect(oled.glass.chrome.liveBlur, isFalse);
      expect(oled.glass.chrome.fillOpacity, AppOpacity.nearOpaqueDark);
    });

    test('oled is dark-only — light mode falls back to standard', () {
      final oledLight = resolveAppTheme(
        _inputs(Brightness.light, AppSurfaceStyle.oled),
      );
      final standardLight = resolveAppTheme(
        _inputs(Brightness.light, AppSurfaceStyle.standard),
      );
      expect(oledLight.surfaces.canvas, standardLight.surfaces.canvas);
      expect(oledLight.surfaces.card, standardLight.surfaces.card);
    });

    test('high contrast raises muted text and border visibility', () {
      for (final b in [Brightness.light, Brightness.dark]) {
        final hc = resolveAppTheme(_inputs(b, AppSurfaceStyle.highContrast));
        final std = resolveAppTheme(_inputs(b, AppSurfaceStyle.standard));
        double contrast(Color a, Color bg) {
          final la = a.computeLuminance();
          final lb = bg.computeLuminance();
          final hi = la > lb ? la : lb;
          final lo = la > lb ? lb : la;
          return (hi + 0.05) / (lo + 0.05);
        }

        expect(
          contrast(hc.content.muted, hc.surfaces.card),
          greaterThan(contrast(std.content.muted, std.surfaces.card)),
          reason: '${b.name}: high contrast must not soften muted text',
        );
        expect(
          contrast(hc.surfaces.border, hc.surfaces.card),
          greaterThan(contrast(std.surfaces.border, std.surfaces.card)),
          reason: '${b.name}: high contrast must strengthen borders',
        );
        expect(hc.glass.sheet.liveBlur, isFalse);
        expect(hc.glass.sheet.fillOpacity, AppOpacity.opaque);
      }
    });

    test('standard surfaces retain role-specific live glass', () {
      final standard = resolveAppTheme(
        _inputs(Brightness.light, AppSurfaceStyle.standard),
      );

      expect(standard.glass.chrome.liveBlur, isTrue);
      expect(standard.glass.sheet.blurSigma, AppBlur.sheet);
      expect(
        standard.glass.sticky.fillOpacity,
        greaterThan(standard.glass.chrome.fillOpacity),
      );
    });

    test('forui theme surfaces follow the style', () {
      final oled = buildAppForuiTheme(
        brightness: Brightness.dark,
        touch: true,
        surfaceStyle: AppSurfaceStyle.oled,
      );
      expect(oled.colors.background, const Color(0xFF000000));
      final resolved = resolveAppTheme(
        _inputs(Brightness.dark, AppSurfaceStyle.oled),
      );
      expect(oled.colors.card, resolved.surfaces.card);
    });
  });

  group('SurfaceStyleController', () {
    test('persists and restores the preference', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = SurfaceStyleController(prefs);
      expect(controller.state, AppSurfaceStyle.standard);

      await controller.set(AppSurfaceStyle.oled);
      expect(prefs.getString('naviwealth.theme.surface_style'), 'oled');
      expect(SurfaceStyleController(prefs).state, AppSurfaceStyle.oled);
    });

    test('unknown persisted keys fall back to standard', () {
      expect(AppSurfaceStyle.fromKey('nope'), AppSurfaceStyle.standard);
      expect(AppSurfaceStyle.fromKey(null), AppSurfaceStyle.standard);
    });
  });
}
