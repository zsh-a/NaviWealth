import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';

/// Status colors that aren't directionally tied to market gain/loss.
///
/// Direction-sensitive colors live on [MarketColors] because they swap based
/// on user preference. This extension stays stable across all market color
/// modes — `success` is always green, `danger` is always red.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
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

  factory SemanticColors.light() => const SemanticColors(
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
    info: ColorPalette.cyan500,
    onInfo: ColorPalette.neutral0,
    infoContainer: ColorPalette.cyan50,
    onInfoContainer: ColorPalette.cyan700,
    divider: ColorPalette.neutral200,
    scrim: Color(0x66000000),
  );

  factory SemanticColors.dark() => const SemanticColors(
    success: ColorPalette.green300,
    onSuccess: ColorPalette.green900,
    successContainer: Color(0xFF0D3326),
    onSuccessContainer: ColorPalette.green100,
    warning: Color(0xFFF5B544),
    onWarning: ColorPalette.amber700,
    warningContainer: Color(0xFF3D2A05),
    onWarningContainer: ColorPalette.amber100,
    danger: ColorPalette.red300,
    onDanger: ColorPalette.red900,
    dangerContainer: Color(0xFF3F1010),
    onDangerContainer: ColorPalette.red100,
    info: Color(0xFF67D6F0),
    onInfo: ColorPalette.cyan700,
    infoContainer: Color(0xFF06303C),
    onInfoContainer: ColorPalette.cyan100,
    divider: Color(0xFF26303D),
    scrim: Color(0x99000000),
  );

  static SemanticColors of(BuildContext context) =>
      Theme.of(context).extension<SemanticColors>() ?? SemanticColors.light();

  @override
  SemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? divider,
    Color? scrim,
  }) {
    return SemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      divider: divider ?? this.divider,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDangerContainer: Color.lerp(
        onDangerContainer,
        other.onDangerContainer,
        t,
      )!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}
