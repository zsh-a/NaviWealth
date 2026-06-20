import 'package:flutter/material.dart';

/// Primitive color palette — raw values only.
///
/// Higher layers compose these into semantic / market tokens. UI code should
/// not import this file directly; reach for [SemanticColors] or [MarketColors]
/// instead so visuals stay swappable per theme/preference.
class ColorPalette {
  const ColorPalette._();

  // ── Accent (Tailwind teal) — legacy brand interaction color ─────────────
  // Retained for backward compatibility; new code should use cyanBrand.
  static const Color teal50 = Color(0xFFF0FDFA);
  static const Color teal100 = Color(0xFFCCFBF1);
  static const Color teal200 = Color(0xFF99F6E4);
  static const Color teal300 = Color(0xFF5EEAD4);
  static const Color teal400 = Color(0xFF2DD4BF);
  static const Color teal500 = Color(0xFF14B8A6);
  static const Color teal600 = Color(0xFF0D9488);
  static const Color teal700 = Color(0xFF0F766E);
  static const Color teal800 = Color(0xFF115E59);
  static const Color teal900 = Color(0xFF134E4A);

  // ── Cyan brand (spec primary) — bright turquoise interaction color ─────
  // The primary brand hue per the fintech UI spec. cyanBrand500 is the
  // light-mode foreground; cyanBrand400 is the dark-mode foreground.
  static const Color cyanBrand50 = Color(0xFFEAFBFC);
  static const Color cyanBrand100 = Color(0xFFD0F7F9);
  static const Color cyanBrand200 = Color(0xFFA8EFF2);
  static const Color cyanBrand300 = Color(0xFF7AE8EC);
  static const Color cyanBrand400 = Color(0xFF6BE8E8); // dark mode primary fg
  static const Color cyanBrand500 = Color(0xFF3BC6D9); // light mode primary fg
  static const Color cyanBrand600 = Color(0xFF17A8B0);
  static const Color cyanBrand700 = Color(0xFF138A90);
  static const Color cyanBrand800 = Color(0xFF0F6D72);
  static const Color cyanBrand900 = Color(0xFF0A4F52);

  // ── Navy (spec text) — deep blue-black, not pure black ────────────────
  // Primary text color per the fintech UI spec. navy900 is the default
  // foreground; navy300 is the muted/secondary text.
  static const Color navy50 = Color(0xFFF0F5F7);
  static const Color navy100 = Color(0xFFD8E3E7);
  static const Color navy200 = Color(0xFFB5C5CB);
  static const Color navy300 = Color(0xFF8F9BB3);
  static const Color navy400 = Color(0xFF6B838A);
  static const Color navy500 = Color(0xFF4D666D);
  static const Color navy600 = Color(0xFF3A5058);
  static const Color navy700 = Color(0xFF2A3B42);
  static const Color navy800 = Color(0xFF1A2830);
  static const Color navy900 = Color(0xFF111827);
  static const Color navy950 = Color(0xFF002A38);
  static const Color navyGlass = Color(0xFF0F2A35);
  static const Color navySoftBorder = Color(0xFFCAD7DA);

  // ── Secondary accent (warm orange) — low-frequency highlights ─────────
  static const Color secondary500 = Color(0xFFFA6400);

  // ── Brand (NaviWealth blue, derived from legacy seed 0xFF1F6FEB) ────────
  // Retained as info / secondary accent (Sync banner, FxRate badges, etc.).
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
  static const Color neutral75 = Color(0xFFF1F5F5); // cool-toned surface tint
  static const Color neutralTint = Color(0xFFEAF4F5);
  static const Color neutralGlass = Color(0xFFF7FAFA);
  static const Color neutralGlassBorder = Color(0xFFE3ECEE);
  static const Color neutralCardRaised = Color(0xFFF7FBFB);
  static const Color neutralCardHero = Color(0xFFF1F7F8);
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

  // ── Profit / gain (emerald) ─────────────────────────────────────────────
  // Migrated from legacy "standard green" #16A34A to Tailwind emerald
  // to give profit a softer, more premium read against dark surfaces
  // while still hitting WCAG AA on light backgrounds. The 500 / 600 pair is
  // the canonical fg used by [MarketColors] (dark mode / light mode resp.).
  static const Color green50 = Color(0xFFECFDF5);
  static const Color green100 = Color(0xFFD1FAE5);
  static const Color green300 = Color(0xFF6EE7B7);
  static const Color green500 = Color(0xFF10B981); // emerald — dark mode fg
  static const Color green600 = Color(0xFF059669); // emerald — light mode fg
  static const Color green700 = Color(0xFF047857);
  static const Color green900 = Color(0xFF064E3B);
  static const Color green950 = Color(0xFF0F3D22);

  // ── Loss / danger (rose / soft crimson) ─────────────────────────────────
  // Migrated from saturated red #DC2626 to Tailwind rose. The
  // softer crimson reads less alarming in tight delta columns while staying
  // unambiguously "down" against both light and dark surfaces.
  static const Color red50 = Color(0xFFFFF1F2);
  static const Color red100 = Color(0xFFFFE4E6);
  static const Color red300 = Color(0xFFFDA4AF);
  static const Color red500 = Color(0xFFE11D48); // rose — dark mode fg
  static const Color red600 = Color(0xFFBE123C); // rose — light mode fg
  static const Color red700 = Color(0xFF9F1239);
  static const Color red900 = Color(0xFF4C0519);
  static const Color red950 = Color(0xFF3F1010);

  // ── Ambers (warning) ────────────────────────────────────────────────────
  static const Color amber50 = Color(0xFFFEF6E5);
  static const Color amber100 = Color(0xFFFCE7B0);
  static const Color amber400 = Color(0xFFF59E0B);
  static const Color amber450 = Color(0xFFF5B544);
  static const Color amber500 = Color(0xFFD97706);
  static const Color amber700 = Color(0xFF8E4E03);
  static const Color amber950 = Color(0xFF3D2A05);

  // ── Cyan / blue accents (info) ──────────────────────────────────────────
  static const Color cyan50 = Color(0xFFE6F4FB);
  static const Color cyan100 = Color(0xFFC2E2F4);
  static const Color cyan500 = Color(0xFF0891B2);
  static const Color cyan600 = Color(0xFF06B6D4);
  static const Color cyan700 = Color(0xFF075E73);
  static const Color cyan950 = Color(0xFF0A3540);

  // ── Overlay / scrim ─────────────────────────────────────────────────────
  static const Color scrimLight = Color(0x66002A38);
  static const Color scrimDark = Color(0x99002A38);

  // ── Violet (knowledge concepts) ────────────────────────────────────────
  static const Color violet500 = Color(0xFF8B5CF6);

  // ── Orange (knowledge / expense accent) ────────────────────────────────
  static const Color orange500 = Color(0xFFF97316);

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

/// Knowledge-type accent colours.
///
/// Each knowledge object type maps to a distinct hue so detail pages,
/// library lists, and decision pages read as a varied palette. Values
/// match the Tailwind-derived scale used across the design system.
class KnowledgeTypeColors {
  const KnowledgeTypeColors._();

  static const Color principle = ColorPalette.green500; // emerald
  static const Color assumption = ColorPalette.amber400; // amber
  static const Color concept = ColorPalette.violet500; // violet
  static const Color experiment = ColorPalette.cyan600; // cyan
  static const Color routine = ColorPalette.orange500; // orange
}

/// Expense-category accent colours.
///
/// Each expense icon maps to a distinct hue so the picker, list, and report
/// screens read as a varied palette rather than a flat red block. Values are
/// Tailwind-derived and chosen to stay accessible against both light and dark
/// surfaces. The default seed accent (red500) is intentionally omitted from
/// this map — callers treat its absence as "use the category hue".
class ExpenseCategoryColors {
  const ExpenseCategoryColors._();

  static const Color orange = Color(0xFFF97316); // restaurant, fastfood
  static const Color amber = ColorPalette.amber500; // local_cafe
  static const Color lime = Color(0xFF65A30D); // grocery, shopping_cart
  static const Color sky = Color(0xFF0EA5E9); // car, bus
  static const Color skyDark = Color(0xFF0284C7); // taxi
  static const Color indigo = Color(0xFF6366F1); // home
  static const Color slate = Color(0xFF64748B); // apartment
  static const Color yellow = Color(0xFFEAB308); // utilities (bolt)
  static const Color teal = ColorPalette.cyanBrand500; // furniture (chair)
  static const Color purple = Color(
    0xFFA855F7,
  ); // entertainment (esports, movie)
  static const Color red = ColorPalette.red500; // medical_services
  static const Color rose = ColorPalette.red600; // local_hospital
  static const Color emerald = ColorPalette.green600; // education (school)
  static const Color pink = Color(0xFFEC4899); // shopping_bag
  static const Color blue = ColorPalette.brand500; // flight
  static const Color slateDark = Color(0xFF475569); // phone, credit_card
  static const Color amberLight = Color(0xFFF59E0B); // gifts
  static const Color violet = Color(0xFF8B5CF6); // pets
  static const Color emeraldLight = ColorPalette.green500; // fitness
  static const Color cyan = ColorPalette.cyan500; // category
  static const Color gray = ColorPalette.neutral500; // receipts, more
}
