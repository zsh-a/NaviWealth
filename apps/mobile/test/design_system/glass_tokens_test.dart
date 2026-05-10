// Post-glass smoke tests for the surface hairline tokens. The blur /
// ThemeExtension behaviour from the glass era was deleted along with
// the liquid_glass_widgets dependency; these tests cover the flat
// helper that took its place.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  group('GlassTokens (flat helper)', () {
    test('blur is retired (always 0)', () {
      expect(GlassTokens.dark().blurSigma, 0);
      expect(GlassTokens.light().blurSigma, 0);
    });

    test('surfaceColor differs between brightnesses', () {
      expect(GlassTokens.dark().surfaceColor,
          isNot(GlassTokens.light().surfaceColor));
    });

    test('hairlineColor is barely visible in both modes', () {
      // Hairlines are ~5–10% alpha so cards read as discrete surfaces
      // without a heavy outline.
      expect(GlassTokens.dark().hairlineColor.a, lessThan(0.2));
      expect(GlassTokens.light().hairlineColor.a, lessThan(0.2));
    });

    test('borderRadius is shared across brightnesses', () {
      expect(
        GlassTokens.dark().borderRadius,
        GlassTokens.light().borderRadius,
      );
    });

    testWidgets('GlassTokens.of resolves from the active brightness', (
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
      await tester.pumpAndSettle();

      expect(light.surfaceColor, isNot(dark.surfaceColor));
    });

    test('isSupported returns false post-migration', () {
      expect(GlassTokens.isSupported(), isFalse);
    });
  });
}
