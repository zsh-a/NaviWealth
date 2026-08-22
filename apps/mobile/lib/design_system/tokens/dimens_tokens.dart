import 'package:flutter/painting.dart';

import 'color_palette.dart';

/// Spacing + corner-radius scale.
///
/// Source of truth for the `spacing` / `radius` groups in
/// `apps/mobile/design_tokens/tokens.json` (the JSON is generated from
/// these Dart values by `tool/export_design_tokens.dart`; see
/// `design_tokens/README.md`).
///
/// Exposed so chrome (sheets, cards, headers) references the scale
/// instead of inlining magic numbers, which is what makes a global
/// restyle a one-file change.
class AppSpacing {
  const AppSpacing._();

  static const double s0 = 0;
  static const double hairline = 1;
  static const double s2 = 2;
  static const double accentBar = 3;
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

/// Page composition rhythm — prefer these over ad-hoc spacing between modules.
///
/// - [section]: major beats (hero → metrics → timeline)
/// - [module]: related cards in one column
/// - [row]: dense list rows / chips
class AppPageRhythm {
  const AppPageRhythm._();

  static const double section = AppSpacing.s24;
  static const double module = AppSpacing.s16;
  static const double row = AppSpacing.s8;

  static const EdgeInsets cardPadding = EdgeInsets.all(AppSpacing.s16);
  static const EdgeInsets heroPadding = EdgeInsets.all(AppSpacing.s20);
  static const EdgeInsets densePadding = EdgeInsets.all(AppSpacing.s12);
}

class AppStroke {
  const AppStroke._();

  static const double none = 0;
  static const double hairline = 1;
  static const double thin = 1.2;
  static const double medium = 1.5;
  static const double branch = 2;
  static const double sparkline = 2.2;
  static const double accent = 3;
  static const double handle = 3.5;
  static const double indicator = 4;
  static const double halo = 6;
}

class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;

  /// Hero cards, large glass docks, and marquee surfaces.
  static const double xl = 20;

  static const double full = 9999;
}

/// Semantic opacity scale.
///
/// Replaces raw `withValues(alpha: ...)` magic numbers with named tokens.
/// Values are chosen from the most frequent alpha literals in the codebase
/// (see design token audit 2026-05-31).
class AppOpacity {
  const AppOpacity._();

  /// Fully transparent -- gradient endpoints, invisible unselected fills.
  static const double transparent = 0.0;

  /// Tiny hover tint on light surfaces. (~0.02)
  static const double hoverTint = 0.02;

  /// Tiny hover tint on dark surfaces. (~0.03)
  static const double hoverTintDark = 0.03;

  /// Barely visible -- hairline dividers, ghost backgrounds. (~0.04)
  static const double whisper = 0.04;

  /// Very subtle -- faint tint layers. (~0.06)
  static const double faint = 0.06;

  /// Soft tint for low-emphasis accent containers. (~0.08)
  static const double softTint = 0.08;

  /// Subtle -- selection highlights, icon tints, card surfaces. (~0.10)
  static const double subtle = 0.10;

  /// Light -- secondary highlights, soft accents. (~0.12)
  static const double light = 0.12;

  /// Medium -- visible but not dominant accents. (~0.14)
  static const double medium = 0.14;

  /// Soft accent container fill. (~0.15)
  static const double accentContainer = 0.15;

  /// Highlight -- accent bars, subtle emphasis. (~0.20)
  static const double highlight = 0.20;

  /// Hover/hero-dot halo. (~0.25)
  static const double halo = 0.25;

  /// Muted -- borders, muted backgrounds, secondary text. (~0.30)
  static const double muted = 0.30;

  /// Hero profit-glow base alpha. (~0.40)
  static const double glow = 0.40;

  /// Disabled / dimmed -- container fills, de-emphasized content. (~0.40)
  static const double disabled = 0.40;

  /// Scrim / overlay backdrop. (~0.50)
  static const double scrim = 0.50;

  /// Prominent -- emphasized text, active states. (~0.60)
  static const double prominent = 0.60;

  /// Strong -- high-emphasis foreground. (~0.70)
  static const double strong = 0.70;

  /// Emphasis -- stronger than [strong] but below overlay. (~0.80)
  static const double emphasis = 0.80;

  /// Overlay -- near-opaque overlays, greeting text. (~0.85)
  static const double overlay = 0.85;

  /// Solid surface overlay -- opaque chart/tooltips without flattening. (~0.94)
  static const double solidSurface = 0.94;

  /// Near-opaque -- frosted glass surface fills. (~0.97)
  static const double nearOpaque = 0.97;

  /// Near-opaque variant -- darker glass surfaces. (~0.98)
  static const double nearOpaqueDark = 0.98;

  /// Fully opaque.
  static const double opaque = 1.0;
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

  /// Floating navigation and compact sticky chrome.
  static const double chrome = 14;

  /// Standard sheet / dialog blur.
  static const double sheet = 18;
}

/// Canonical shadow sets keyed by surface role.
///
/// Shadows use the navy text color (#002A38) at low opacity for a soft,
/// tinted look that matches the fintech spec — no harsh black shadows.
class AppShadow {
  const AppShadow._();

  /// Subtle chip / badge shadow — minimal depth.
  static const List<BoxShadow> elevation1 = [
    BoxShadow(
      color: ColorPalette.shadowNavy04,
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  /// Standard elevation — FABs, scroll-to-bottom buttons.
  static const List<BoxShadow> elevation2 = [
    BoxShadow(
      color: ColorPalette.shadowNavy04,
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Standard card shadow — subtle depth.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: ColorPalette.shadowNavy04,
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  /// Dark raised modules — soft black lift so cards leave the canvas.
  static const List<BoxShadow> cardDark = [
    BoxShadow(
      color: ColorPalette.shadowDarkRaised,
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];

  /// Card hover / pressed state — slightly deeper.
  static const List<BoxShadow> cardHover = [
    BoxShadow(
      color: ColorPalette.shadowNavy08,
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];

  /// Hero card — deeper ambient shadow + brand whisper.
  static const List<BoxShadow> hero = [
    BoxShadow(
      color: ColorPalette.shadowNavy08,
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: ColorPalette.shadowCyan04,
      blurRadius: 40,
      offset: Offset(0, 16),
    ),
  ];

  /// Dark hero — depth plus a restrained cyan halo.
  static const List<BoxShadow> heroDark = [
    BoxShadow(
      color: ColorPalette.shadowDarkHero,
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: ColorPalette.shadowCyan04,
      blurRadius: 28,
      offset: Offset(0, 6),
    ),
  ];

  /// Left-edge panel shadow — desktop side panels.
  static const List<BoxShadow> panel = [
    BoxShadow(
      color: ColorPalette.shadowNavy10,
      blurRadius: 24,
      offset: Offset(-8, 0),
    ),
  ];

  /// Desktop sheet elevation — floating overlays.
  static const List<BoxShadow> desktopSheet = [
    BoxShadow(
      color: ColorPalette.shadowNavy10,
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];

  /// Update banner shadow — bottom-edge accent.
  static const List<BoxShadow> banner = [
    BoxShadow(
      color: ColorPalette.shadowNavy10,
      blurRadius: 12,
      offset: Offset(0, -2),
    ),
  ];

  /// Floating glass nav bar — one restrained elevation layer.
  static const List<BoxShadow> nav = [
    BoxShadow(
      color: ColorPalette.shadowNavy10,
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
}

/// Canonical chart container heights.
///
/// Keeps sparkline and full chart heights consistent across features.
class AppChartHeights {
  const AppChartHeights._();

  /// Tiny inline sparkline inside compact metric cards.
  static const double sparkline = AppSpacing.s28;

  /// Compact card chart / chart-shaped loading state.
  static const double compact = 140;

  /// Standard chart in detail pages and dashboard cards.
  static const double standard = 180;

  /// Full-width chart in dedicated analytics views.
  static const double full = 220;
}

/// Canonical heights for fixed-format controls.
class AppControlHeights {
  const AppControlHeights._();

  /// Minimum interactive target shared by touch and pointer layouts.
  ///
  /// Visual glyphs may remain compact inside this box, but the hit region
  /// must never shrink below the iOS 44pt baseline.
  static const double touchTarget = 44;

  /// Desktop/sidebar collapse affordance height.
  static const double sidebarToggle = AppSpacing.s40;

  /// Horizontal chip/filter rail with compact pill controls.
  static const double chipRail = touchTarget;

  /// Denser horizontal chip/filter rail used under search fields.
  static const double compactChipRail = touchTarget;

  /// Drag-hit area at the top of floating sheets.
  static const double sheetDragHandleHitArea = AppIconSizes.lg;

  /// Compact time/value picker strip inside settings sheets.
  static const double pickerStrip = 44;

  /// Compact loading placeholder that keeps cards from collapsing.
  static const double compactLoadingState = 96;

  /// Portfolio overview rail containing compact allocation cards.
  static const double portfolioOverviewRail = 164;

  /// Search results viewport inside a standard bottom sheet.
  static const double searchSheet = 460;
}

/// Canonical widths for fixed-format controls and chart side panels.
class AppControlWidths {
  const AppControlWidths._();

  /// Tablet sidebar rail width.
  static const double tabletRail = 80;

  /// AI chat sessions side panel width.
  static const double aiSessionsPanel = 320;

  /// Horizontal AI action card width.
  static const double aiActionCard = 240;

  /// Compact create action at the end of the portfolio overview rail.
  static const double portfolioCreateCard = 128;

  /// Portfolio summary card in the horizontal overview rail.
  static const double portfolioOverviewCard = 224;

  /// Markdown ordered-list marker column.
  static const double markdownMarker = AppIconSizes.h18;

  /// Fixed label column in compact key/value diagnostic rows.
  static const double detailLabel = 96;

  /// Compact value/skeleton column in dense financial rows.
  static const double compactValue = 80;

  /// Compact AI result label/value column.
  static const double aiCompactColumn = AppSpacing.s64;

  /// Key column in compact JSON/payload review rows.
  static const double payloadKey = 104;

  /// Segmented feedback control in compact proposal review cards.
  static const double feedbackSegmented = 220;

  /// Large donut chart in AI-rendered compact cards.
  static const double aiDonut = 88;

  /// Left tree-label column in AI trace waterfall rows.
  static const double traceTreeLabel = 150;

  /// Compact duration column in AI trace waterfall rows.
  static const double traceDuration = AppSpacing.s56;

  /// Key column in AI trace detail key/value rows.
  static const double traceDetailKey = 76;

  /// Fixed label column in AI runtime diagnostics rows.
  static const double runtimeLabel = 86;

  /// Short setting labels and action buttons with predictable copy length.
  static const double settingsShortLabel = 72;

  /// Compact trailing percentage/value column in slider setting rows.
  static const double settingsShortValue = 44;

  /// Narrow index column for dense tabular schedules.
  static const double scheduleIndex = AppSpacing.s48;

  /// Numeric/date columns in dense tabular schedules.
  static const double scheduleValue = 100;

  /// Side-by-side chart rail that must hold a compact circular chart.
  static const double chartSidePanel = 232;

  /// Segmented controls with short labels in desktop/tablet rows.
  static const double segmentedCompact = 260;

  /// Compact metric tile in analytical wrap layouts.
  static const double metricTile = 148;

  /// Minimum readable Bento module width at the default text scale.
  static const double bentoTile = 320;

  /// Maximum width for a centred empty-state action. Leaves enough room for
  /// localized labels at large text scales while remaining compact.
  static const double emptyStateAction = 320;

  /// Short statistic tile in sheet summary grids.
  static const double statsTile = 140;

  /// Fixed suffix column for compact scenario summaries.
  static const double scenarioSuffix = 110;
}
