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

  /// Circular soft primary fill — dense card primary actions.
  softPrimary,

  /// Circular soft primary fill + primary hairline ring (dock Ask AI).
  softPrimaryRing,

  /// Squircle soft primary fill + ring (Knowledge review tools).
  softPrimaryTile,

  /// Soft primary fill, square-ish radius — selected dock / rail items.
  softSelected,

  /// Circular soft muted fill — secondary compact tools.
  softMuted,
}

/// Standardised tappable icon for chrome surfaces.
///
/// Replaces the scattered `_ShellIconButton`, `_OverlayIconButton`,
/// `_AskAiDockButton` and `_ReviewIconButton` patterns with a single
/// configurable widget.  All icon buttons in the app should route through
/// this class so tooltip semantics, press feedback, and sizing stay
/// consistent.
class AppIconButton extends StatefulWidget {
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

  /// Soft primary circular action (Execution done / resume / progress).
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
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final resolvedIconSize = widget.iconSize ?? AppIconSizes.md;
    final resolvedSize = widget.size < AppControlHeights.touchTarget
        ? AppControlHeights.touchTarget
        : widget.size;
    final colors = context.theme.colors;
    final resolvedIconColor =
        widget.iconColor ??
        switch (widget.surface) {
          AppIconButtonSurface.plain => colors.foreground,
          AppIconButtonSurface.softPrimary ||
          AppIconButtonSurface.softPrimaryRing ||
          AppIconButtonSurface.softPrimaryTile ||
          AppIconButtonSurface.softSelected ||
          AppIconButtonSurface.softMuted => colors.primary,
        };

    final enabled = !widget.busy && widget.onPress != null;
    var resolvedDecoration = widget.decoration ?? _surfaceDecoration(colors);
    // Desktop hover state (citizenship audit §7): a quiet foreground tint on
    // every surface, including plain chrome icons that previously had none.
    if (_hovered && enabled) {
      final tint = colors.foreground.withValues(alpha: AppOpacity.faint);
      final base = resolvedDecoration;
      resolvedDecoration = base == null
          ? BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(_focusRadius),
            )
          : base.copyWith(
              color: base.color == null
                  ? tint
                  : Color.alphaBlend(tint, base.color!),
            );
    }

    Widget button = Semantics(
      container: true,
      label: widget.tooltip,
      button: true,
      enabled: enabled,
      onTap: widget.busy ? null : widget.onPress,
      excludeSemantics: true,
      child: FTappable(
        onPress: widget.busy ? null : widget.onPress,
        onHoverChange: (hovered) => setState(() => _hovered = hovered),
        focusedOutlineStyle: FFocusedOutlineStyleDelta.delta(
          borderRadius: BorderRadius.circular(_focusRadius),
        ),
        child: AnimatedContainer(
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
          margin: widget.margin,
          decoration: resolvedDecoration,
          alignment: Alignment.center,
          child: widget.busy
              ? SizedBox(
                  width: resolvedIconSize,
                  height: resolvedIconSize,
                  child: const FCircularProgress(
                    size: FCircularProgressSizeVariant.xs,
                  ),
                )
              : Icon(
                  widget.icon,
                  size: resolvedIconSize,
                  color: resolvedIconColor,
                ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = FTooltip(
        tipBuilder: (_, _) => Text(widget.tooltip!),
        child: button,
      );
    }

    return button;
  }

  /// Focus-ring / hover shape: plain icons get a small rounding instead of
  /// a hard rectangle.
  double get _focusRadius =>
      _resolvedRadius == 0 ? AppRadius.sm : _resolvedRadius;

  double get _resolvedRadius =>
      widget.borderRadius ??
      switch (widget.surface) {
        AppIconButtonSurface.plain => 0,
        AppIconButtonSurface.softPrimary ||
        AppIconButtonSurface.softPrimaryRing ||
        AppIconButtonSurface.softMuted => AppRadius.full,
        AppIconButtonSurface.softPrimaryTile ||
        AppIconButtonSurface.softSelected => AppRadius.sm,
      };

  BoxDecoration? _surfaceDecoration(FColors colors) {
    final radius = BorderRadius.circular(_resolvedRadius);
    return switch (widget.surface) {
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
        border: Border.all(
          color: colors.primary.withValues(alpha: AppOpacity.light),
          width: AppStroke.hairline,
        ),
      ),
      AppIconButtonSurface.softSelected => BoxDecoration(
        color: colors.primary.withValues(alpha: AppOpacity.subtle),
        borderRadius: radius,
      ),
      AppIconButtonSurface.softMuted => BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.medium),
        borderRadius: radius,
      ),
    };
  }
}
