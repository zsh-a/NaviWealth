import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';

/// Standardised tappable icon for chrome surfaces.
///
/// Replaces the scattered `_ShellIconButton`, `_OverlayIconButton`,
/// `_AskAiDockButton` and `_ReviewIconButton` patterns with a single
/// configurable widget.  All icon buttons in the app should route through
/// this class so tooltip semantics, press feedback, and sizing stay
/// consistent.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPress,
    this.tooltip,
    this.size = 40,
    this.iconSize,
    this.iconColor,
    this.decoration,
    this.margin,
    this.busy = false,
  });

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

  /// Icon colour.  Defaults to `colors.foreground`.
  final Color? iconColor;

  /// Custom box decoration.  When null the button is a plain undecorated
  /// square — the most common shell-chrome pattern.
  final BoxDecoration? decoration;

  /// Outer margin around the button.
  final EdgeInsetsGeometry? margin;

  /// When true the icon is replaced by a small spinner and [onPress] is
  /// ignored.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final resolvedIconSize = iconSize ?? AppIconSizes.md;
    final colors = context.theme.colors;

    Widget button = Semantics(
      label: tooltip,
      button: true,
      child: FTappable(
        onPress: busy ? null : onPress,
        child: Container(
          width: size,
          height: size,
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
                  color: iconColor ?? colors.foreground,
                ),
        ),
      ),
    );

    if (tooltip != null) {
      button = FTooltip(tipBuilder: (_, _) => Text(tooltip!), child: button);
    }

    return button;
  }
}
