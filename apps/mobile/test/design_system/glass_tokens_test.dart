import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  group('GlassTokens', () {
    test('dark variant blurs harder than light', () {
      // The dark wash is heavier so the layer underneath is hinted-not-
      // legible; light wash is softer so text reads cleanly through it.
      expect(GlassTokens.dark().blurSigma, greaterThan(GlassTokens.light().blurSigma));
      expect(GlassTokens.dark().blurSigma, 24);
      expect(GlassTokens.light().blurSigma, 16);
    });

    test('surfaceColor alpha is below 1.0 for both brightnesses', () {
      // The whole point — a transparent wash so the BackdropFilter content
      // bleeds through. If alpha hit 1.0 it'd be an opaque card.
      expect(GlassTokens.dark().surfaceColor.a, lessThan(1.0));
      expect(GlassTokens.light().surfaceColor.a, lessThan(1.0));
    });

    test('hairlineColor is barely visible in both modes', () {
      // Hairlines define a glass card's edge against an HDR backdrop —
      // 6% alpha is the spec value (FIR-104).
      expect(GlassTokens.dark().hairlineColor.a, closeTo(0.06, 0.02));
      expect(GlassTokens.light().hairlineColor.a, closeTo(0.06, 0.02));
    });

    test('borderRadius is shared across brightnesses', () {
      expect(GlassTokens.dark().borderRadius, GlassTokens.light().borderRadius);
    });

    testWidgets('GlassTokens.of resolves from the active theme', (
      tester,
    ) async {
      late GlassTokens light;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (ctx) {
              light = GlassTokens.of(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      late GlassTokens dark;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (ctx) {
              dark = GlassTokens.of(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Theme cross-fades on swap — settle the lerp before reading.
      await tester.pumpAndSettle();

      expect(light.blurSigma, 16);
      expect(dark.blurSigma, 24);
      expect(light.surfaceColor, isNot(dark.surfaceColor));
    });

    test('lerp interpolates blur sigma + colors halfway', () {
      final mid = GlassTokens.light().lerp(GlassTokens.dark(), 0.5);
      // 16 → 24 lerped at 0.5 = 20.
      expect(mid.blurSigma, 20);
      // Color lerp falls back to itself if invalid; here both have alpha.
      expect(mid.surfaceColor.a, lessThan(1.0));
    });
  });

  group('AppTheme injects GlassTokens', () {
    test('light theme exposes a GlassTokens extension', () {
      final theme = AppTheme.light();
      expect(theme.extension<GlassTokens>(), isNotNull);
      expect(theme.extension<GlassTokens>()!.blurSigma, 16);
    });

    test('dark theme exposes a GlassTokens extension', () {
      final theme = AppTheme.dark();
      expect(theme.extension<GlassTokens>(), isNotNull);
      expect(theme.extension<GlassTokens>()!.blurSigma, 24);
    });
  });
}
