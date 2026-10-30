import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Visual surface behind an [AppIconButton].
///
/// Prefer these tokens over ad-hoc [BoxDecoration] at call sites so action
/// chips (Execution, dock tools, review actions) stay consistent.
enum AppIconButtonSurface {
  /// Undecorated chrome icon (default shell header pattern).
  plain,

  /// Soft primary fill — dense card primary actions.
  softPrimary,

  /// Circular soft primary fill + primary hairline ring (dock Ask AI).
  softPrimaryRing,

  /// Rounded soft primary fill (compact review tools).
  softPrimaryTile,

  /// Soft primary fill, square-ish radius — selected dock / rail items.
  softSelected,

  /// Rounded soft muted fill — secondary compact tools.
  softMuted,
}

/// Standardised tappable icon for chrome surfaces.
///
/// Replaces the scattered `_ShellIconButton`, `_OverlayIconButton`,
/// `_AskAiDockButton` and `_ReviewIconButton` patterns with a single
/// configurable widget. All icon buttons in the app should route through
/// this class so tooltip semantics, press feedback, and sizing stay
/// consistent.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPress,
    this.tooltip,
    this.size = AppControlHeights.touchTarget,
    this.iconSize,
    this.iconColor,
    this.surface = AppIconButtonSurface.plain,
    this.borderRadius,
    this.decoration,
    this.margin,
    this.busy = false,
  });

  /// Soft primary action (Execution done / resume / progress).
  const AppIconButton.softPrimary({
    Key? key,
    required IconData icon,
    required VoidCallback? onPress,
    String? tooltip,
    double size = AppControlHeights.touchTarget,
    double? iconSize = AppIconSizes.xs,
    Color? iconColor,
    EdgeInsetsGeometry? margin,
    bool busy = false,
  }) : this(
         key: key,
         icon: icon,
         onPress: onPress,
         tooltip: tooltip,
         size: size,
         iconSize: iconSize,
         iconColor: iconColor,
         surface: AppIconButtonSurface.softPrimary,
         margin: margin,
         busy: busy,
       );

  /// Soft primary circular action with a hairline primary ring.
  const AppIconButton.softPrimaryRing({
    Key? key,
    required IconData icon,
    required VoidCallback? onPress,
    String? tooltip,
    double size = 48,
    double? iconSize = AppIconSizes.mlg,
    Color? iconColor,
    EdgeInsetsGeometry? margin,
    bool busy = false,
  }) : this(
         key: key,
         icon: icon,
         onPress: onPress,
         tooltip: tooltip,
         size: size,
         iconSize: iconSize,
         iconColor: iconColor,
         surface: AppIconButtonSurface.softPrimaryRing,
         margin: margin,
         busy: busy,
       );

  /// Soft primary squircle tile (review / inbox tool buttons).
  const AppIconButton.softPrimaryTile({
    Key? key,
    required IconData icon,
    required VoidCallback? onPress,
    String? tooltip,
    double size = AppControlHeights.touchTarget,
    double? iconSize = AppIconSizes.xs,
    Color? iconColor,
    EdgeInsetsGeometry? margin,
    bool busy = false,
  }) : this(
         key: key,
         icon: icon,
         onPress: onPress,
         tooltip: tooltip,
         size: size,
         iconSize: iconSize,
         iconColor: iconColor,
         surface: AppIconButtonSurface.softPrimaryTile,
         margin: margin,
         busy: busy,
       );

  /// The icon to display.
  final IconData icon;

  /// Tap callback.  Ignored (button appears disabled) when [busy] is true.
  final VoidCallback? onPress;

  /// Optional tooltip shown on long-press / hover.
  final String? tooltip;

  /// Outer dimension of the tappable area (width == height).
  final double size;

  /// Icon glyph size.  Defaults to [AppIconSizes.md] (20).
  final double? iconSize;

  /// Icon colour.  Defaults to `colors.foreground` for [AppIconButtonSurface.plain],
  /// `colors.primary` for soft surfaces when null.
  final Color? iconColor;

  /// Canonical surface token. Ignored when [decoration] is non-null.
  final AppIconButtonSurface surface;

  /// Optional radius override for [surface] (e.g. dock Life uses [AppRadius.md]).
  final double? borderRadius;

  /// Escape hatch for one-off chrome. Prefer [surface] for product UI.
  final BoxDecoration? decoration;

  /// Outer margin around the button.
  final EdgeInsetsGeometry? margin;

  /// When true the icon is replaced by a small spinner and [onPress] is
  /// ignored.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final resolvedIconSize = iconSize ?? AppIconSizes.md;
    final resolvedSize = size < AppControlHeights.touchTarget
        ? AppControlHeights.touchTarget
        : size;
    final colors = context.theme.colors;
    final resolvedIconColor =
        iconColor ??
        switch (surface) {
          AppIconButtonSurface.plain ||
          AppIconButtonSurface.softMuted => colors.foreground,
          AppIconButtonSurface.softPrimary ||
          AppIconButtonSurface.softPrimaryRing ||
          AppIconButtonSurface.softPrimaryTile ||
          AppIconButtonSurface.softSelected => colors.primary,
        };

    final enabled = !busy && onPress != null;
    final baseDecoration = decoration ?? _surfaceDecoration(context, colors);
    final radius = _resolvedRadius(context);

    Widget button = Semantics(
      container: true,
      label: tooltip,
      button: true,
      enabled: enabled,
      onTap: busy ? null : onPress,
      excludeSemantics: true,
      child: FTappable(
        style: context.theme.buttonStyles.ghost.md.tappableStyle,
        onPress: busy ? null : onPress,
        focusedOutlineStyle: FFocusedOutlineStyleDelta.delta(
          borderRadius: radius,
        ),
        builder: (context, variants, _) {
          var decoration = baseDecoration;
          final pressed =
              enabled && variants.contains(FTappableVariant.pressed);
          final hovered =
              enabled && variants.contains(FTappableVariant.hovered);
          if (pressed || hovered) {
            final tint = colors.foreground.withValues(
              alpha: pressed ? AppOpacity.light : AppOpacity.faint,
            );
            decoration = decoration == null
                ? BoxDecoration(color: tint, borderRadius: radius)
                : decoration.copyWith(
                    color: Color.alphaBlend(
                      tint,
                      decoration.color ?? colors.card,
                    ),
                  );
          }
          return AnimatedContainer(
            duration: AppMotionPolicy.duration(
              context,
              Motion.fast,
              role: AppMotionRole.decorative,
            ),
            curve: Motion.standardDecelerate,
            constraints: const BoxConstraints(
              minWidth: AppControlHeights.touchTarget,
              minHeight: AppControlHeights.touchTarget,
            ),
            width: resolvedSize,
            height: resolvedSize,
            margin: margin,
            decoration: decoration,
            alignment: Alignment.center,
            child: busy
                ? SizedBox(
                    width: resolvedIconSize,
                    height: resolvedIconSize,
                    child: const FCircularProgress(
                      size: FCircularProgressSizeVariant.xs,
                    ),
                  )
                : Icon(
                    icon,
                    size: resolvedIconSize,
                    color: enabled
                        ? resolvedIconColor
                        : resolvedIconColor.withValues(
                            alpha: AppOpacity.disabled,
                          ),
                  ),
          );
        },
      ),
    );

    if (tooltip != null) {
      button = FTooltip(tipBuilder: (_, _) => Text(tooltip!), child: button);
    }

    return button;
  }

  // The dock's explicit ring remains circular; ordinary action surfaces share
  // the text buttons' theme-owned shape, including the refined preset.
  BorderRadiusGeometry _resolvedRadius(BuildContext context) =>
      borderRadius != null
      ? BorderRadius.circular(borderRadius!)
      : surface == AppIconButtonSurface.softPrimaryRing
      ? BorderRadius.circular(AppRadius.full)
      : context.theme.buttonStyles.ghost.md.focusedOutlineStyle.borderRadius;

  BoxDecoration? _surfaceDecoration(BuildContext context, FColors colors) {
    final radius = _resolvedRadius(context);
    return switch (surface) {
      AppIconButtonSurface.plain => null,
      AppIconButtonSurface.softPrimary => BoxDecoration(
        color: colors.primary.withValues(alpha: AppOpacity.subtle),
        borderRadius: radius,
      ),
      AppIconButtonSurface.softPrimaryRing => BoxDecoration(
        color: colors.primary.withValues(alpha: AppOpacity.subtle),
        borderRadius: radius,
        border: Border.all(
          color: colors.primary.withValues(alpha: AppOpacity.muted),
          width: AppStroke.hairline,
        ),
      ),
      AppIconButtonSurface.softPrimaryTile => BoxDecoration(
        color: colors.primary.withValues(alpha: AppOpacity.subtle),
        borderRadius: radius,
      ),
      AppIconButtonSurface.softSelected => BoxDecoration(
        color: colors.primary.withValues(alpha: AppOpacity.subtle),
        borderRadius: radius,
      ),
      AppIconButtonSurface.softMuted => BoxDecoration(
        color: Color.alphaBlend(
          colors.foreground.withValues(alpha: AppOpacity.faint),
          colors.card,
        ),
        borderRadius: radius,
      ),
    };
  }
}
