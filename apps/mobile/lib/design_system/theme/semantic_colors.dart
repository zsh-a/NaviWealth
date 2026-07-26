import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';

/// Status colors that aren't directionally tied to market gain/loss.
///
/// Direction-sensitive colors live on [MarketColors] (which can swap based
/// on user preference). These tokens stay stable across all market color
/// modes — `success` is always green, `danger` is always red.
///
/// Forui's [FColors] doesn't carry success/warning/info; this small object
/// fills the gap. `divider` aliases forui's `colors.border` at call sites
/// where preferred.
@immutable
class SemanticColors {
  const SemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.divider,
    required this.scrim,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  final Color divider;
  final Color scrim;

  static const SemanticColors light = SemanticColors(
    success: ColorPalette.green600,
    onSuccess: ColorPalette.neutral0,
    successContainer: ColorPalette.green50,
    onSuccessContainer: ColorPalette.green900,
    warning: ColorPalette.amber500,
    onWarning: ColorPalette.neutral0,
    warningContainer: ColorPalette.amber50,
    onWarningContainer: ColorPalette.amber700,
    danger: ColorPalette.red600,
    onDanger: ColorPalette.neutral0,
    dangerContainer: ColorPalette.red50,
    onDangerContainer: ColorPalette.red900,
    // cyanBrand700, not 500: the bright interaction cyan sits at ~2:1 on
    // white and was effectively invisible as an info foreground
    // (doc 15 §3.1; enforced by theme_contrast_test.dart).
    info: ColorPalette.cyanBrand700,
    onInfo: ColorPalette.neutral0,
    infoContainer: ColorPalette.cyanBrand50,
    onInfoContainer: ColorPalette.cyanBrand900,
    divider: ColorPalette.navy100,
    scrim: ColorPalette.scrimLight,
  );

  static const SemanticColors dark = SemanticColors(
    success: ColorPalette.green300,
    onSuccess: ColorPalette.green900,
    successContainer: ColorPalette.green950,
    onSuccessContainer: ColorPalette.green100,
    warning: ColorPalette.amber450,
    onWarning: ColorPalette.amber700,
    warningContainer: ColorPalette.amber950,
    onWarningContainer: ColorPalette.amber100,
    danger: ColorPalette.red300,
    onDanger: ColorPalette.red900,
    dangerContainer: ColorPalette.red950,
    onDangerContainer: ColorPalette.red100,
    info: ColorPalette.cyanBrand400,
    onInfo: ColorPalette.navy950,
    infoContainer: ColorPalette.cyan950,
    onInfoContainer: ColorPalette.cyanBrand100,
    divider: ColorPalette.navy800,
    scrim: ColorPalette.scrimDark,
  );

  /// Resolve the appropriate set from the surrounding theme brightness.
  static SemanticColors of(BuildContext context) =>
      FTheme.of(context).colors.brightness == Brightness.dark ? dark : light;
}
