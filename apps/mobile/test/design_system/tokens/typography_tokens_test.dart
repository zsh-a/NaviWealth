import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/tokens/typography_tokens.dart';

void main() {
  group('TypographyTokens numeric aliases', () {
    // The numeric scale is a semantic alias layer over the main type scale —
    // these expectations pin the exact resolved render parameters so the
    // aliasing refactor stays visually equivalent.
    void expectStyle(
      TextStyle style, {
      required double size,
      required double height,
      required FontWeight weight,
      double letterSpacing = 0,
      String fontFamily = TypographyTokens.fontFamilySans,
    }) {
      expect(style.fontSize, size);
      expect(style.height, height);
      expect(style.fontWeight, weight);
      expect(style.letterSpacing, letterSpacing);
      expect(style.fontFamily, fontFamily);
      expect(style.fontFamilyFallback, TypographyTokens.fontFamilyFallback);
      expect(style.fontFeatures, TypographyTokens.tabularFigures);
    }

    test('numericDisplay resolves to 32/1.12 w700 -0.4', () {
      expectStyle(
        TypographyTokens.numericDisplay,
        size: 32,
        height: 1.12,
        weight: FontWeight.w700,
        letterSpacing: -0.4,
      );
    });

    test('numericTitle resolves to 20/1.3 w600', () {
      expectStyle(
        TypographyTokens.numericTitle,
        size: 20,
        height: 1.3,
        weight: FontWeight.w600,
      );
    });

    test('numericTitleStrong resolves to 20/1.3 w700', () {
      expectStyle(
        TypographyTokens.numericTitleStrong,
        size: 20,
        height: 1.3,
        weight: FontWeight.w700,
      );
    });

    test('numericBody resolves to 14/1.4 w500', () {
      expectStyle(
        TypographyTokens.numericBody,
        size: 14,
        height: 1.4,
        weight: FontWeight.w500,
      );
    });

    test('numericBodyStrong resolves to 14/1.4 w700', () {
      expectStyle(
        TypographyTokens.numericBodyStrong,
        size: 14,
        height: 1.4,
        weight: FontWeight.w700,
      );
    });

    test('numericCaption resolves to 12/1.3 w500', () {
      expectStyle(
        TypographyTokens.numericCaption,
        size: 12,
        height: 1.3,
        weight: FontWeight.w500,
      );
    });

    test('numericCaptionStrong resolves to 12/1.3 w600', () {
      expectStyle(
        TypographyTokens.numericCaptionStrong,
        size: 12,
        height: 1.3,
        weight: FontWeight.w600,
      );
    });

    test('numericMono resolves to 14/1.4 w500 monospace', () {
      expectStyle(
        TypographyTokens.numericMono,
        size: 14,
        height: 1.4,
        weight: FontWeight.w500,
        fontFamily: TypographyTokens.fontFamilyMono,
      );
    });

    test('chartCaption floor is 11px, aligned with labelSmall', () {
      expectStyle(
        TypographyTokens.chartCaption,
        size: 11,
        height: 1.3,
        weight: FontWeight.w500,
      );
      expect(
        TypographyTokens.chartCaption.fontSize,
        TypographyTokens.labelSmall.fontSize,
      );
    });
  });
}
