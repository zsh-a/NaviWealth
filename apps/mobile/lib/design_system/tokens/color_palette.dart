import 'package:flutter/material.dart';

/// Primitive color palette — raw values only.
///
/// Higher layers compose these into semantic / market tokens. UI code should
/// not import this file directly; reach for [SemanticColors] or [MarketColors]
/// instead so visuals stay swappable per theme/preference.
class ColorPalette {
  const ColorPalette._();

  // ── Cyan brand (spec primary) — bright turquoise interaction color ─────
  // The primary brand hue per the fintech UI spec. Interaction foregrounds
  // resolve through AccentColors so text contrast can differ from chart and
  // decorative cyan roles.
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
  // Re-derived into the cyan-gray navy hue family (was Tailwind slate
  // #8F9BB3, a blue-purple outlier). navy300 is the dark-mode muted
  // foreground, so its hue tints every secondary line of dark text.
  static const Color navy300 = Color(0xFF90A6AD);
  static const Color navy400 = Color(0xFF6B838A);
  static const Color navy500 = Color(0xFF4D666D);
  static const Color navy600 = Color(0xFF3A5058);
  static const Color navy700 = Color(0xFF344A55);
  static const Color navy800 = Color(0xFF203641);
  static const Color navy900 = Color(0xFF111827);
  // Dark surfaces intentionally stay neutral-navy. The previous green-biased
  // canvas made every surface read as branded and flattened the elevation
  // ladder; cyan is now reserved for interaction and data emphasis.
  static const Color navy950 = Color(0xFF071821);
  static const Color navyGlass = Color(0xFF101F2A);
  static const Color navyRaised = Color(0xFF142936);
  static const Color navyHero = Color(0xFF1B3542);
  static const Color navySoftBorder = Color(0xFFCAD7DA);

  // ── OLED surfaces (AppSurfaceStyle.oled, dark only) ────────────────────
  // True-black canvas with the card ladder pulled down two steps so the
  // elevation rhythm survives on pitch black. Hues stay in the navy family.
  static const Color oledCanvas = Color(0xFF000000);
  static const Color oledCard = Color(0xFF0A121A);
  static const Color oledRaised = Color(0xFF0F1B26);
  static const Color oledHero = Color(0xFF152532);

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

  // ── Light surfaces ──────────────────────────────────────────────────────
  // Cool canvas + pure white modules. SoftCard differentiates levels with
  // shadow / hero wash rather than stacking near-identical greys.
  static const Color surfaceBackground = Color(0xFFF4F7F7);
  static const Color surface = neutral0;
  static const Color surfaceRaised = neutral0;
  static const Color surfaceOverlay = Color(0xFFEEF6F7);
  static const Color surfaceHairline = Color(0xFFD5E0E2);

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
  static const Color greenContainerDark = Color(0xFF053527);

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
  static const Color redContainerDark = Color(0xFF3F0A1A);

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
  static const Color shadowMedium = Color(0x33000000);
  static const Color shadowDarkRaised = Color(0x40000000);
  static const Color shadowDarkHero = Color(0x66000000);
  static const Color scrimLight = Color(0x66002A38);
  static const Color scrimDark = Color(0x99002A38);
  static const Color shadowNavy04 = Color(0x0A002A38);
  static const Color shadowNavy08 = Color(0x14002A38);
  static const Color shadowNavy10 = Color(0x1A002A38);
  static const Color shadowCyan04 = Color(0x0A3BC6D9);
  static const Color profitGlowDark = Color(0x6610B981);
  static const Color profitGlowLight = Color(0x66059669);

  // ── Violet (knowledge concepts + accent seed ramp) ─────────────────────
  static const Color violet50 = Color(0xFFF5F3FF);
  static const Color violet100 = Color(0xFFEDE9FE);
  static const Color violet400 = Color(0xFFA78BFA);
  static const Color violet500 = Color(0xFF8B5CF6);
  static const Color violet700 = Color(0xFF6D28D9);
  static const Color violet800 = Color(0xFF5B21B6);
  static const Color violet900 = Color(0xFF4C1D95);

  // ── Indigo (accent seed ramp) ──────────────────────────────────────────
  static const Color indigo50 = Color(0xFFEEF2FF);
  static const Color indigo100 = Color(0xFFE0E7FF);
  static const Color indigo400 = Color(0xFF818CF8);
  static const Color indigo700 = Color(0xFF4338CA);
  static const Color indigo800 = Color(0xFF3730A3);
  static const Color indigo900 = Color(0xFF312E81);

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

  // ── Chart categorical series accents ─────────────────────────────────
  // Chart-only sequence tokens. Regular UI controls should keep using
  // semantic / market tokens instead of these categorical hues.
  static const Color chartCyanDark = Color(0xFF67D6F0);
  static const Color chartPurpleDark = Color(0xFFB497F1);
  static const Color chartEmeraldDark = Color(0xFF34D399);
  static const Color chartPinkDark = Color(0xFFEB7BB1);
  static const Color chartYellowDark = Color(0xFFE8D45A);
  static const Color chartBlueDark = Color(0xFF7AB7FB);
  static const Color chartRoseDark = Color(0xFFFB7185);

  static const Color chartPurpleLight = Color(0xFF7C3AED);
  static const Color chartPinkLight = Color(0xFFDB2777);
  static const Color chartYellowLight = Color(0xFFCA8A04);
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
/// Named tokens for expense UI (picker chips, list avatars, report pie).
/// Hex values match `kExpenseCategorySeedHexByPath` in the Finance expense
/// domain — keep both sides in lockstep when adjusting hues.
///
/// Palette rules:
/// - every taxonomy leaf has a unique hex
/// - hues are stepped for categorical charts (not brand monochrome)
/// - neutrals reserved for long-tail / "other" / fee-like buckets
class ExpenseCategoryColors {
  const ExpenseCategoryColors._();

  static const Color dining = Color(0xFFEA580C);
  static const Color groceries = Color(0xFF65A30D);
  static const Color coffee = Color(0xFFCA8A04);
  static const Color transport = Color(0xFF0284C7);
  static const Color rideHailing = Color(0xFF0F766E);
  static const Color housing = Color(0xFF4F46E5);
  static const Color utilities = Color(0xFFEAB308);
  static const Color household = Color(0xFF0891B2);
  static const Color shopping = Color(0xFFDB2777);
  static const Color subscriptions = Color(0xFF7C3AED);
  static const Color entertainment = Color(0xFFC026D3);
  static const Color medical = Color(0xFFE11D48);
  static const Color fitness = Color(0xFF059669);
  static const Color education = Color(0xFF2563EB);
  static const Color travel = Color(0xFF1D4ED8);
  static const Color communication = Color(0xFF0E7490);
  static const Color gift = Color(0xFFD97706);
  static const Color familySupport = Color(0xFFBE123C);
  static const Color pets = Color(0xFF9333EA);
  static const Color trading = Color(0xFF334155);
  static const Color tradingFee = Color(0xFF64748B);
  static const Color tradingTax = Color(0xFF9F1239);
  static const Color tradingInterest = Color(0xFF475569);
  static const Color tax = Color(0xFFB91C1C);
  static const Color taxWithholding = Color(0xFF881337);
  static const Color other = Color(0xFF6B7280);

  // Icon-only extras (custom categories / aliases).
  static const Color fastfood = Color(0xFFF97316);
  static const Color car = Color(0xFF0369A1);
  static const Color apartment = Color(0xFF6366F1);
  static const Color movie = Color(0xFFA855F7);
  static const Color hospital = Color(0xFFFB7185);
  static const Color redeem = Color(0xFFF43F5E);
  static const Color category = Color(0xFF06B6D4);

  /// Muted roll-up colour for pie "Other" slices.
  static const Color pieOther = other;
}
