import 'package:flutter/painting.dart';

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
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s56 = 56;
  static const double s64 = 64;
}

class AppRadius {
  const AppRadius._();

  static const double none = 0;
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xlg = 18;
  static const double xl = 20;
  static const double xxl = 28;
  static const double card = 20; // spec: normal cards 16-24
  static const double cardLg = 40; // spec: large cards 32-40
  static const double nav = 40; // spec: bottom nav 36-44
  static const double full = 9999;
}

/// Semantic opacity scale.
///
/// Replaces raw `withValues(alpha: ...)` magic numbers with named tokens.
/// Values are chosen from the most frequent alpha literals in the codebase
/// (see design token audit 2026-05-31).
class AppOpacity {
  const AppOpacity._();

  /// Barely visible -- hairline dividers, ghost backgrounds. (~0.04)
  static const double whisper = 0.04;

  /// Very subtle -- faint tint layers. (~0.06)
  static const double faint = 0.06;

  /// Subtle -- selection highlights, icon tints, card surfaces. (~0.10)
  static const double subtle = 0.10;

  /// Light -- secondary highlights, soft accents. (~0.12)
  static const double light = 0.12;

  /// Medium -- visible but not dominant accents. (~0.14)
  static const double medium = 0.14;

  /// Highlight -- accent bars, subtle emphasis. (~0.20)
  static const double highlight = 0.20;

  /// Muted -- borders, muted backgrounds, secondary text. (~0.30)
  static const double muted = 0.30;

  /// Disabled / dimmed -- container fills, de-emphasized content. (~0.40)
  static const double disabled = 0.40;

  /// Scrim / overlay backdrop. (~0.50)
  static const double scrim = 0.50;

  /// Prominent -- emphasized text, active states. (~0.60)
  static const double prominent = 0.60;

  /// Strong -- high-emphasis foreground. (~0.70)
  static const double strong = 0.70;

  /// Overlay -- near-opaque overlays, greeting text. (~0.85)
  static const double overlay = 0.85;

  /// Near-opaque -- frosted glass surface fills. (~0.97)
  static const double nearOpaque = 0.97;

  /// Near-opaque variant -- darker glass surfaces. (~0.98)
  static const double nearOpaqueDark = 0.98;
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

  /// Slightly larger than sm — used for inline icons that need more presence
  /// (e.g. delta arrows, status indicators in tight rows).
  static const double h18 = 18;

  /// List-row leading icons, sheet tile prefix icons.
  static const double md = 20;

  /// Mid-large -- tablet rail / dock icons between md and lg.
  static const double mlg = 22;

  /// Toolbar / primary-action icons.
  static const double lg = 24;

  /// Illustrative icons in empty states / headers.
  static const double xl = 32;

  /// Hero icons in onboarding / large empty states.
  static const double xxl = 40;

  /// Large hero icons for full-page empty states and splash screens.
  static const double hero = 48;

  /// Extra-large hero icons for prominent empty-state illustrations.
  static const double heroLg = 56;
}

/// Backdrop blur sigma values for frosted-glass surfaces.
class AppBlur {
  const AppBlur._();

  /// Standard sheet / dialog blur.
  static const double sheet = 18;

  /// Floating glass nav bar blur.
  static const double nav = 18;
}

/// Canonical shadow sets keyed by surface role.
///
/// Shadows use the navy text color (#002A38) at low opacity for a soft,
/// tinted look that matches the fintech spec — no harsh black shadows.
class AppShadow {
  const AppShadow._();

  /// Standard card shadow — subtle depth.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A002A38), blurRadius: 28, offset: Offset(0, 10)),
  ];

  /// Card hover / pressed state — slightly deeper.
  static const List<BoxShadow> cardHover = [
    BoxShadow(color: Color(0x14002A38), blurRadius: 36, offset: Offset(0, 14)),
  ];

  /// Floating glass nav bar — soft ambient glow.
  static const List<BoxShadow> nav = [
    BoxShadow(color: Color(0x1A002A38), blurRadius: 36, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x0A3BC6D9), blurRadius: 20, offset: Offset(0, -2)),
  ];
}

/// Canonical chart container heights.
///
/// Keeps sparkline and full chart heights consistent across features.
class AppChartHeights {
  const AppChartHeights._();

  /// Mini sparkline in dashboard cards.
  static const double mini = 132;

  /// Standard chart in detail pages.
  static const double standard = 160;

  /// Full-width chart in dedicated analytics views.
  static const double full = 220;
}
