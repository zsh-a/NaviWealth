/// L2 component specs (blueprint doc 15, §6.3).
///
/// Geometry and interaction budgets are decided once here and consumed by
/// the design-system components — call sites never re-derive padding, radius
/// or press coefficients. Specs are resolved by `resolveAppTheme` and read
/// via `context.appTheme.<spec>`.
library;

import 'package:flutter/widgets.dart';

import '../tokens/dimens_tokens.dart';

/// Press feedback — one coefficient for the whole app.
///
/// Replaces the 0.985 / 0.97 / 0.96 / 0.99 zoo that made otherwise identical
/// tap targets settle differently.
@immutable
class PressSpec {
  const PressSpec({required this.scale});

  /// Scale applied while pressed.
  final double scale;
}

/// Card geometry budget consumed by `SoftCard`.
@immutable
class CardSpec {
  const CardSpec({
    required this.padding,
    required this.densePadding,
    required this.heroPadding,
    required this.radius,
    required this.heroRadius,
  });

  /// Standard module inset — the only sanctioned padding for regular cards.
  final EdgeInsets padding;

  /// Dense list tiles and compact modules.
  final EdgeInsets densePadding;

  /// Page-level hero anchors.
  final EdgeInsets heroPadding;

  /// Corner radius for flat/raised cards.
  final double radius;

  /// Corner radius for hero cards.
  final double heroRadius;
}

/// Badge geometry consumed by `AppBadge`.
@immutable
class BadgeSpec {
  const BadgeSpec({
    required this.regularPadding,
    required this.compactPadding,
    required this.radius,
  });

  final EdgeInsets regularPadding;
  final EdgeInsets compactPadding;
  final double radius;
}

/// Divider treatment consumed by `AppDivider`.
@immutable
class DividerSpec {
  const DividerSpec({
    required this.inset,
    required this.thickness,
    required this.opacity,
  });

  /// Horizontal inset from the parent card edge.
  final double inset;

  final double thickness;

  /// Alpha applied to the foreground color.
  final double opacity;
}

/// Metric tile budget consumed by `AppMetricCluster`.
@immutable
class MetricTileSpec {
  const MetricTileSpec({required this.minWidth});

  final double minWidth;
}

/// Semantic roles for the small number of surfaces allowed to use live blur.
///
/// Content modules stay opaque `SoftCard` surfaces. Glass is application
/// chrome: navigation, sticky context, modal sheets, and temporary overlays.
enum AppGlassRole { chrome, sticky, sheet, overlay }

/// Visual status only. The owning control still owns actions and semantics.
enum AppGlassStatus { idle, busy, disabled, error }

/// Opt-in soft-light chrome. These are visual budgets, not a physical glass
/// simulation. Dense surfaces retain their existing, more opaque material.
@immutable
class SoftGlassSpec {
  const SoftGlassSpec();

  double chromeFillOpacity(Brightness brightness) =>
      brightness == Brightness.dark ? 0.88 : 0.78;
  double washOpacity(Brightness brightness) =>
      brightness == Brightness.dark ? 0.025 : 0.065;
  double rimOpacity(Brightness brightness) =>
      brightness == Brightness.dark ? 0.10 : 0.25;
  double touchOpacity(Brightness brightness) =>
      brightness == Brightness.dark ? 0.08 : 0.16;

  double get touchRadius => 96;

  /// Relative material thickness for the four chrome roles. Sheets and
  /// overlays sit above scrolling content, while the dock stays quieter.
  double depthFor(AppGlassRole role) => switch (role) {
    AppGlassRole.chrome => 0.72,
    AppGlassRole.sticky => 0.88,
    AppGlassRole.sheet => 1.0,
    AppGlassRole.overlay => 1.08,
  };

  double specularOpacity(Brightness brightness, AppGlassRole role) =>
      (brightness == Brightness.dark ? 0.055 : 0.11) * depthFor(role);

  double occlusionOpacity(Brightness brightness, AppGlassRole role) =>
      (brightness == Brightness.dark ? 0.035 : 0.05) * depthFor(role);

  double edgeHighlightOpacity(Brightness brightness, AppGlassRole role) =>
      (brightness == Brightness.dark ? 0.14 : 0.20) * depthFor(role);

  double edgeShadeOpacity(Brightness brightness, AppGlassRole role) =>
      (brightness == Brightness.dark ? 0.10 : 0.08) * depthFor(role);

  double stateOpacity(Brightness brightness) =>
      brightness == Brightness.dark ? 0.08 : 0.06;

  /// Kept as a token for callers that need to describe a state rim, but the
  /// painter intentionally uses one shared edge highlight in the resting
  /// state so glass does not turn into a collection of bright outlines.
  double get stateRimOpacity => 0.18;
  double get selectedEmphasis => 0.42;
  double get hoverEmphasis => 0.22;
  double get focusEmphasis => 0.65;
  double get pressedEmphasis => 0.82;
  double get busyEmphasis => 0.25;
  double get errorEmphasis => 0.42;
  double get disabledWash => 0.30;
}

const SoftGlassSpec kAppSoftGlassSpec = SoftGlassSpec();

@immutable
class GlassMaterialSpec {
  const GlassMaterialSpec({
    required this.blurSigma,
    required this.fillOpacity,
    required this.borderOpacity,
    required this.liveBlur,
  });

  final double blurSigma;
  final double fillOpacity;
  final double borderOpacity;
  final bool liveBlur;
}

/// Theme-owned glass language resolved from accessibility and surface style.
@immutable
class GlassSpec {
  const GlassSpec({
    required this.chrome,
    required this.sticky,
    required this.sheet,
    required this.overlay,
  });

  final GlassMaterialSpec chrome;
  final GlassMaterialSpec sticky;
  final GlassMaterialSpec sheet;
  final GlassMaterialSpec overlay;

  GlassMaterialSpec resolve(AppGlassRole role) => switch (role) {
    AppGlassRole.chrome => chrome,
    AppGlassRole.sticky => sticky,
    AppGlassRole.sheet => sheet,
    AppGlassRole.overlay => overlay,
  };
}

/// The resolved spec set. Values are density/brightness-invariant today but
/// resolve through the theme so a future axis (compact desktop chrome, …)
/// changes one function, not every component.
const PressSpec kAppPressSpec = PressSpec(scale: 0.98);

const CardSpec kAppCardSpec = CardSpec(
  padding: AppPageRhythm.cardPadding,
  densePadding: AppPageRhythm.densePadding,
  heroPadding: AppPageRhythm.heroPadding,
  radius: AppRadius.md,
  heroRadius: AppRadius.lg,
);

const BadgeSpec kAppBadgeSpec = BadgeSpec(
  regularPadding: EdgeInsets.symmetric(
    horizontal: AppSpacing.s8,
    vertical: AppSpacing.s4,
  ),
  compactPadding: EdgeInsets.symmetric(
    horizontal: AppSpacing.s8,
    vertical: AppSpacing.s2,
  ),
  radius: AppRadius.full,
);

const DividerSpec kAppDividerSpec = DividerSpec(
  inset: AppSpacing.s14,
  thickness: AppStroke.hairline,
  opacity: AppOpacity.whisper,
);

const MetricTileSpec kAppMetricTileSpec = MetricTileSpec(
  minWidth: AppControlWidths.metricTile,
);
