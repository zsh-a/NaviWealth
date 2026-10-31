import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Visual presets share navigation, form state and accessibility behavior.
enum AppVisualStyle {
  classic,
  refined;

  String get persistedKey => name;

  static AppVisualStyle fromKey(String? key) =>
      values.where((value) => value.name == key).firstOrNull ?? refined;

  AppVisualSpec get spec => switch (this) {
    classic => kClassicVisualSpec,
    refined => kRefinedVisualSpec,
  };
}

const kClassicVisualSpec = AppVisualSpec(
  continuousCorners: false,
  controlRadius: 10,
  surfaceRadius: AppRadius.lg,
  sheetRadius: AppRadius.lg,
  overlayRadius: AppRadius.lg,
  cardGradient: false,
  cardBorders: false,
  cardShadows: false,
  sheetDuration: Motion.medium,
  sheetCurve: Curves.easeOutCubic,
);

const kRefinedVisualSpec = AppVisualSpec(
  continuousCorners: true,
  controlRadius: AppRadius.lg,
  surfaceRadius: AppRadius.lg,
  sheetRadius: AppRadius.xxl,
  overlayRadius: AppRadius.xxl,
  cardGradient: false,
  cardBorders: false,
  cardShadows: false,
  sheetDuration: Motion.ambient,
  sheetCurve: AppSheetSpringCurve(),
);

/// Independent of the visual preset; navigation keeps content and forms solid.
enum AppMaterialStyle {
  solid,
  navigation,
  translucent;

  String get persistedKey => name;

  static AppMaterialStyle fromKey(String? key) =>
      values.where((value) => value.name == key).firstOrNull ?? navigation;
}

@immutable
class AppVisualSpec {
  const AppVisualSpec({
    required this.continuousCorners,
    required this.controlRadius,
    required this.surfaceRadius,
    required this.sheetRadius,
    required this.overlayRadius,
    required this.cardGradient,
    required this.cardBorders,
    required this.cardShadows,
    required this.sheetDuration,
    required this.sheetCurve,
  });

  final bool continuousCorners;
  final double controlRadius;
  final double surfaceRadius;
  final double sheetRadius;
  final double overlayRadius;
  final bool cardGradient;
  final bool cardBorders;
  final bool cardShadows;
  final Duration sheetDuration;
  final Curve sheetCurve;

  ShapeBorder shape(BorderRadius radius, {BorderSide side = BorderSide.none}) =>
      continuousCorners
      ? RoundedSuperellipseBorder(borderRadius: radius, side: side)
      : RoundedRectangleBorder(borderRadius: radius, side: side);

  Decoration decoration({
    required BorderRadius radius,
    Color? color,
    Gradient? gradient,
    BorderSide side = BorderSide.none,
    List<BoxShadow>? shadows,
  }) => continuousCorners
      ? ShapeDecoration(
          color: color,
          gradient: gradient,
          shape: shape(radius, side: side),
          shadows: shadows,
        )
      : BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: radius,
          border: side == BorderSide.none ? null : Border.fromBorderSide(side),
          boxShadow: shadows,
        );
}

/// Normalized critically damped spring: no overshoot outside route bounds.
class AppSheetSpringCurve extends Curve {
  const AppSheetSpringCurve();

  @override
  double transformInternal(double t) {
    const rate = 8.0;
    return (1 - (1 + rate * t) * math.exp(-rate * t)) /
        (1 - (1 + rate) * math.exp(-rate));
  }
}
