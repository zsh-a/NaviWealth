import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'app_visual_style.dart';
import 'component_specs.dart';

/// Ordinary actions use a light tonal fill; final submissions opt into filled.
enum AppButtonEmphasis { tonal, filled }

// Forui compares motion values by tween identity during theme updates.
final _buttonPressTween = FImmutableTween<double>(
  begin: 1,
  end: kAppPressSpec.scale,
);

/// One button language for direct Forui controls and app-owned actions.
FButtonStyles buildAppButtonStyles({
  required FColors colors,
  required FTypography typography,
  required FStyle style,
  required bool touch,
  required bool highContrast,
  required AppVisualStyle visualStyle,
}) {
  FButtonSizeStyles sizes(FButtonVariant variant) {
    FButtonStyle button(FButtonSizeVariant size) => buildAppButtonStyle(
      colors: colors,
      typography: typography,
      style: style,
      touch: touch,
      highContrast: highContrast,
      visual: visualStyle.spec,
      variant: variant,
      size: size,
    );
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

/// Submission emphasis reuses normal geometry, focus, disabled state and motion.
FButtonStyle buildAppButtonStyle({
  required FColors colors,
  required FTypography typography,
  required FStyle style,
  required bool touch,
  required bool highContrast,
  required AppVisualSpec visual,
  required FButtonVariant variant,
  required FButtonSizeVariant size,
  AppButtonEmphasis emphasis = AppButtonEmphasis.tonal,
}) {
  final dark = colors.brightness == Brightness.dark;
  final primary = variant == FButtonVariant.primary;
  final danger = variant == FButtonVariant.destructive;
  final ghost = variant == FButtonVariant.ghost;
  final outline = variant == FButtonVariant.outline;
  final transparent = colors.card.withValues(alpha: AppOpacity.transparent);
  final secondary = Color.alphaBlend(
    colors.foreground.withValues(
      alpha: dark ? AppOpacity.hoverTintDark : AppOpacity.hoverTint,
    ),
    colors.card,
  );
  final foreground = primary
      ? colors.primary
      : danger
      ? colors.destructive
      : colors.foreground;
  final fill = primary || danger
      ? Color.alphaBlend(
          foreground.withValues(
            alpha: primary ? AppOpacity.softTint : AppOpacity.whisper,
          ),
          colors.card,
        )
      : ghost || outline
      ? transparent
      : secondary;

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
        : visual.continuousCorners
        ? AppRadius.lg
        : AppRadius.md,
  );
  final side = highContrast
      ? BorderSide(color: primary ? colors.primary : colors.foreground)
      : outline
      ? BorderSide(color: colors.border)
      : BorderSide.none;
  Decoration decoration(Color color) =>
      visual.decoration(radius: radius, color: color, side: side);
  Color feedback(double opacity) => Color.alphaBlend(
    foreground.withValues(alpha: danger ? opacity / 2 : opacity),
    ghost || outline ? colors.card : fill,
  );
  final constraints = BoxConstraints(minWidth: height, minHeight: height);
  final resolved =
      FButtonStyle.inherit(
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
            [FTappableVariant.hovered]: decoration(
              feedback(AppOpacity.whisper),
            ),
            [FTappableVariant.pressed]: decoration(feedback(AppOpacity.faint)),
            [FTappableVariant.selected]: decoration(feedback(AppOpacity.faint)),
            [FTappableVariant.disabled]: decoration(
              ghost ? transparent : secondary,
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
  return primary && emphasis == AppButtonEmphasis.filled
      ? withFilledAppButtonStyle(resolved, colors)
      : resolved;
}

/// Changes paint only: custom themes, input densities, focus and target geometry
/// remain exactly the same when a primary action becomes a final submission.
FButtonStyle withFilledAppButtonStyle(FButtonStyle base, FColors colors) {
  final dark = colors.brightness == Brightness.dark;
  final fill = Color.alphaBlend(
    (dark ? colors.card : ColorPalette.neutral0).withValues(
      alpha: dark ? AppOpacity.buttonShade : AppOpacity.softTint,
    ),
    colors.primary,
  );
  Decoration recolor(Set<FTappableVariant> variants, double shade) {
    final color = Color.alphaBlend(
      ColorPalette.neutral1000.withValues(alpha: shade),
      fill,
    );
    return switch (base.decoration.resolve(variants)) {
      final BoxDecoration decoration => decoration.copyWith(color: color),
      final ShapeDecoration decoration => ShapeDecoration(
        color: color,
        image: decoration.image,
        shape: decoration.shape,
        shadows: decoration.shadows,
      ),
      final decoration => decoration,
    };
  }

  final text = base.contentStyle.textStyle;
  final icons = base.contentStyle.iconStyle;
  final progress = base.contentStyle.circularProgressStyle;
  final iconOnly = base.iconContentStyle.iconStyle;
  final disabled = {FTappableVariant.disabled};
  return base.copyWith(
    decoration: FVariants(
      recolor({}, AppOpacity.transparent),
      variants: {
        [FTappableVariant.hovered]: recolor({
          FTappableVariant.hovered,
        }, AppOpacity.whisper),
        [FTappableVariant.pressed]: recolor({
          FTappableVariant.pressed,
        }, AppOpacity.faint),
        [FTappableVariant.selected]: recolor({
          FTappableVariant.selected,
        }, AppOpacity.faint),
        [FTappableVariant.disabled]: base.decoration.resolve(disabled),
      },
    ),
    contentStyle: FButtonContentStyleDelta.delta(
      textStyle: FVariants(
        text.resolve({}).copyWith(color: ColorPalette.neutral0),
        variants: {
          [FTappableVariant.disabled]: text.resolve(disabled),
        },
      ),
      iconStyle: FVariants(
        icons.resolve({}).copyWith(color: ColorPalette.neutral0),
        variants: {
          [FTappableVariant.disabled]: icons.resolve(disabled),
        },
      ),
      circularProgressStyle: FVariants(
        progress
            .resolve({})
            .copyWith(
              iconStyle: const IconThemeDataDelta.delta(
                color: ColorPalette.neutral0,
              ),
            ),
        variants: {
          [FTappableVariant.disabled]: progress.resolve(disabled),
        },
      ),
    ),
    iconContentStyle: FButtonIconContentStyleDelta.delta(
      iconStyle: FVariants(
        iconOnly.resolve({}).copyWith(color: ColorPalette.neutral0),
        variants: {
          [FTappableVariant.disabled]: iconOnly.resolve(disabled),
        },
      ),
    ),
  );
}
