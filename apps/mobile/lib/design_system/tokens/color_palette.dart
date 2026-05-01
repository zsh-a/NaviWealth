import 'package:flutter/material.dart';

/// Primitive color palette — raw values only.
///
/// Higher layers compose these into semantic / market tokens. UI code should
/// not import this file directly; reach for [SemanticColors] or [MarketColors]
/// instead so visuals stay swappable per theme/preference.
class ColorPalette {
  const ColorPalette._();

  // ── Brand (NaviWealth blue, derived from legacy seed 0xFF1F6FEB) ────────
  static const Color brand50 = Color(0xFFEFF5FF);
  static const Color brand100 = Color(0xFFDBE8FE);
  static const Color brand200 = Color(0xFFBFD5FD);
  static const Color brand300 = Color(0xFF93B7FB);
  static const Color brand400 = Color(0xFF608FF6);
  static const Color brand500 = Color(0xFF1F6FEB);
  static const Color brand600 = Color(0xFF1758C2);
  static const Color brand700 = Color(0xFF14479C);
  static const Color brand800 = Color(0xFF103A7E);
  static const Color brand900 = Color(0xFF0B2A5C);

  // ── Neutral grayscale ───────────────────────────────────────────────────
  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFF7F8FA);
  static const Color neutral100 = Color(0xFFEFF1F4);
  static const Color neutral200 = Color(0xFFE2E5EA);
  static const Color neutral300 = Color(0xFFCBD0D7);
  static const Color neutral400 = Color(0xFF9AA1AC);
  static const Color neutral500 = Color(0xFF6B7280);
  static const Color neutral600 = Color(0xFF4B5563);
  static const Color neutral700 = Color(0xFF374151);
  static const Color neutral800 = Color(0xFF1F2937);
  static const Color neutral900 = Color(0xFF111827);
  static const Color neutral950 = Color(0xFF0B1220);
  static const Color neutral1000 = Color(0xFF000000);

  // ── Emerald greens (gain / success) ────────────────────────────────────
  // Cooler, luminous emerald tones — premium fintech aesthetic.
  static const Color green50 = Color(0xFFECFDF5);
  static const Color green100 = Color(0xFFD1FAE5);
  static const Color green300 = Color(0xFF6EE7B7);
  static const Color green500 = Color(0xFF10B981);
  static const Color green600 = Color(0xFF059669);
  static const Color green700 = Color(0xFF047857);
  static const Color green900 = Color(0xFF064E3B);

  // ── Soft crimson (loss / danger) ───────────────────────────────────────
  // Desaturated, softer reds — less aggressive, more refined.
  static const Color red50 = Color(0xFFFFF1F2);
  static const Color red100 = Color(0xFFFFE4E6);
  static const Color red300 = Color(0xFFFDA4AF);
  static const Color red500 = Color(0xFFE11D48);
  static const Color red600 = Color(0xFFBE123C);
  static const Color red700 = Color(0xFF9F1239);
  static const Color red900 = Color(0xFF4C0519);

  // ── Ambers (warning) ────────────────────────────────────────────────────
  static const Color amber50 = Color(0xFFFEF6E5);
  static const Color amber100 = Color(0xFFFCE7B0);
  static const Color amber500 = Color(0xFFD97706);
  static const Color amber700 = Color(0xFF8E4E03);

  // ── Cyan / blue accents (info) ──────────────────────────────────────────
  static const Color cyan50 = Color(0xFFE6F4FB);
  static const Color cyan100 = Color(0xFFC2E2F4);
  static const Color cyan500 = Color(0xFF0891B2);
  static const Color cyan700 = Color(0xFF075E73);

  // ── Color-blind friendly accents (Wong / Okabe-Ito palette) ────────────
  // These read distinctly under deuteranopia and protanopia and are used as
  // the "colorblind" market color mode (blue=up, orange=down).
  static const Color cbBlue = Color(0xFF2271B3);
  static const Color cbBlueLight = Color(0xFF6FAEE0);
  static const Color cbBlueDark = Color(0xFF154B7A);
  static const Color cbBlueContainerLight = Color(0xFFE0EEFB);
  static const Color cbBlueContainerDark = Color(0xFF0E2C45);

  static const Color cbOrange = Color(0xFFE69F00);
  static const Color cbOrangeLight = Color(0xFFF6C863);
  static const Color cbOrangeDark = Color(0xFF8A5F00);
  static const Color cbOrangeContainerLight = Color(0xFFFCEED1);
  static const Color cbOrangeContainerDark = Color(0xFF402C00);
}
