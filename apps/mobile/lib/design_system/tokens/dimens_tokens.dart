/// Spacing + corner-radius scale.
///
/// Dart mirror of the `spacing` / `radius` groups in
/// `apps/mobile/design_tokens/tokens.json` (Figma is the source of
/// truth — keep the two in sync; see `design_tokens/README.md`).
///
/// Exposed so chrome (sheets, cards, headers) references the scale
/// instead of inlining magic numbers, which is what makes a global
/// restyle a one-file change.
class AppSpacing {
  const AppSpacing._();

  static const double s0 = 0;
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s56 = 56;
  static const double s64 = 64;
}

class AppRadius {
  const AppRadius._();

  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double full = 9999;
}

/// Canonical icon sizes used across the app's chrome.
///
/// Most icons fall into three buckets: inline ornaments (e.g. delta arrows
/// next to text), affordance icons in rows/buttons, and standalone illustrative
/// icons in empty states / sheet headers. Sticking to this scale keeps the
/// optical rhythm consistent — see `dimens_tokens.dart` for the spacing
/// scale rationale.
class AppIconSizes {
  const AppIconSizes._();

  /// Inline ornaments tucked beside text (delta arrows, status dots).
  static const double xs = 14;

  /// Default for affordance icons in compact rows / chips.
  static const double sm = 16;

  /// List-row leading icons, sheet tile prefix icons.
  static const double md = 20;

  /// Toolbar / primary-action icons.
  static const double lg = 24;

  /// Illustrative icons in empty states / headers.
  static const double xl = 32;

  /// Hero icons in onboarding / large empty states.
  static const double xxl = 40;
}
