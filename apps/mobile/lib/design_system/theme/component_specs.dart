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

/// The resolved spec set. Values are density/brightness-invariant today but
/// resolve through the theme so a future axis (compact desktop chrome, …)
/// changes one function, not every component.
const PressSpec kAppPressSpec = PressSpec(scale: 0.98);

const CardSpec kAppCardSpec = CardSpec(
  padding: AppPageRhythm.cardPadding,
  densePadding: AppPageRhythm.densePadding,
  heroPadding: AppPageRhythm.heroPadding,
  radius: AppRadius.lg,
  heroRadius: AppRadius.xl,
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
