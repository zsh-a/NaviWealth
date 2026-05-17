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
