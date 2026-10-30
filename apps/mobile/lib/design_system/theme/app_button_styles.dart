import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'app_visual_style.dart';
import 'component_specs.dart';

// Reuse the tween: Forui compares motion values by tween identity when deciding
// whether a newly resolved theme needs to animate.
final _buttonPressTween = FImmutableTween<double>(
  begin: 1,
  end: kAppPressSpec.scale,
);

/// One button language for direct Forui controls and app-owned actions.
/// Size describes placement, never whether an action happens asynchronously.
FButtonStyles buildAppButtonStyles({
  required FColors colors,
  required FTypography typography,
  required FStyle style,
  required bool touch,
  required bool highContrast,
  required AppVisualStyle visualStyle,
}) {
  final secondary = Color.alphaBlend(
    colors.foreground.withValues(alpha: AppOpacity.faint),
    colors.card,
  );

  FButtonSizeStyles sizes(FButtonVariant variant) {
    final primary = variant == FButtonVariant.primary;
    final danger = variant == FButtonVariant.destructive;
    final ghost = variant == FButtonVariant.ghost;
    final outline = variant == FButtonVariant.outline;
    final foreground = primary
        ? colors.primaryForeground
        : danger
        ? colors.destructive
        : colors.foreground;
    final fill = primary
        ? colors.primary
        : danger
        ? Color.alphaBlend(
            colors.destructive.withValues(alpha: AppOpacity.softTint),
            colors.card,
          )
        : ghost
        ? colors.card.withValues(alpha: AppOpacity.transparent)
        : outline
        ? colors.card
        : secondary;

    FButtonStyle button(FButtonSizeVariant size) {
      final compact = size == FButtonSizeVariant.xs;
      final large = size == FButtonSizeVariant.lg;
      final height = touch
          ? AppControlHeights.touchTarget
          : compact
          ? 28.0
          : size == FButtonSizeVariant.sm
          ? 32.0
          : large
          ? 40.0
          : 36.0;
      final radius = BorderRadius.circular(
        compact
            ? AppRadius.sm
            : visualStyle == AppVisualStyle.refined
            ? AppRadius.lg
            : AppRadius.md,
      );
      final side = highContrast && !primary
          ? BorderSide(color: colors.foreground)
          : outline
          ? BorderSide(color: colors.border)
          : BorderSide.none;
      Decoration decoration(Color color) =>
          visualStyle.spec.decoration(radius: radius, color: color, side: side);
      Color feedback(double opacity) => Color.alphaBlend(
        (primary ? colors.primaryForeground : foreground).withValues(
          alpha: danger ? opacity / 2 : opacity,
        ),
        ghost ? colors.card : fill,
      );
      final constraints = BoxConstraints(minWidth: height, minHeight: height);
      return FButtonStyle.inherit(
        style: style,
        foregroundColor: foreground,
        disabledForegroundColor: colors.mutedForeground.withValues(
          alpha: AppOpacity.disabled,
        ),
        textStyle: compact ? typography.body.xs : typography.body.sm,
        contentConstraints: constraints,
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.s12 : AppSpacing.s16,
          vertical: large ? AppSpacing.s10 : AppSpacing.s8,
        ),
        contentSpacing: AppSpacing.s8,
        iconConstraints: constraints,
        iconSize: compact ? AppIconSizes.xs : AppIconSizes.sm,
        iconPadding: const EdgeInsets.all(AppSpacing.s8),
        decoration: FVariants(
          decoration(fill),
          variants: {
            [FTappableVariant.hovered]: decoration(feedback(AppOpacity.faint)),
            [FTappableVariant.pressed]: decoration(feedback(AppOpacity.light)),
            [FTappableVariant.selected]: decoration(feedback(AppOpacity.light)),
            [FTappableVariant.disabled]: decoration(
              ghost ? fill : secondary.withValues(alpha: AppOpacity.disabled),
            ),
          },
        ),
      ).copyWith(
        focusedOutlineStyle: FFocusedOutlineStyleDelta.delta(
          borderRadius: radius,
        ),
        tappableStyle: FTappableStyleDelta.delta(
          motion: FTappableMotion(
            bounceTween: _buttonPressTween,
            bounceDownDuration: Motion.fast,
            bounceUpDuration: Motion.fast,
            bounceDownCurve: Motion.standard,
            bounceUpCurve: Motion.standardDecelerate,
          ),
        ),
      );
    }

    final medium = button(FButtonSizeVariant.md);
    return FButtonSizeStyles(
      FVariants(
        medium,
        variants: {
          [FButtonSizeVariant.xs]: button(FButtonSizeVariant.xs),
          [FButtonSizeVariant.sm]: button(FButtonSizeVariant.sm),
          [FButtonSizeVariant.md]: medium,
          [FButtonSizeVariant.lg]: button(FButtonSizeVariant.lg),
        },
      ),
    );
  }

  final primary = sizes(FButtonVariant.primary);
  return FButtonStyles(
    FVariants(
      primary,
      variants: {
        [FButtonVariant.primary]: primary,
        [FButtonVariant.secondary]: sizes(FButtonVariant.secondary),
        [FButtonVariant.outline]: sizes(FButtonVariant.outline),
        [FButtonVariant.ghost]: sizes(FButtonVariant.ghost),
        [FButtonVariant.destructive]: sizes(FButtonVariant.destructive),
      },
    ),
  );
}
