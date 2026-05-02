import 'package:flutter/material.dart';

/// Thin wrapper around [InkWell] that removes Material's splash and
/// highlight overlay, replacing them with a subtle alpha tint on
/// hover / press.
///
/// Use this instead of raw [InkWell] for interactive surfaces that
/// should feel responsive without the Material "ripple" identity.
class AppInkWell extends StatelessWidget {
  const AppInkWell({
    super.key,
    required this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.child,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: borderRadius,
      splashFactory: NoSplash.splashFactory,
      highlightColor: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.04),
      hoverColor: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.04),
      child: child,
    );
  }
}
