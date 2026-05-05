import 'package:flutter/material.dart';

import '../../core/haptics/haptics.dart';
import 'liquid_glass_card.dart';

/// Glass-styled floating action button.
///
/// Uses [LiquidGlassCard] for a frosted-glass look consistent with the
/// app's glass design language. Fires [Haptics.primaryPress] before
/// invoking the caller's `onPressed`.
class AppFab extends StatelessWidget {
  /// Standard circular glass FAB.
  const AppFab({
    super.key,
    required this.onPressed,
    required Widget this.child,
    this.tooltip,
  })  : icon = null,
        label = null,
        _isExtended = false;

  /// Pill-shaped glass FAB with leading [icon] and a [label].
  const AppFab.extended({
    super.key,
    required this.onPressed,
    required Widget this.icon,
    required Widget this.label,
    this.tooltip,
  })  : child = null,
        _isExtended = true;

  final VoidCallback? onPressed;
  final Widget? child;
  final Widget? icon;
  final Widget? label;
  final String? tooltip;
  final bool _isExtended;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wrapped = Haptics.wrapPrimary(onPressed);
    if (_isExtended) {
      return LiquidGlassCard(
        layer: GlassLayer.secondary,
        onTap: wrapped,
        borderRadius: 999,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(color: theme.colorScheme.primary),
              child: icon!,
            ),
            const SizedBox(width: 8),
            DefaultTextStyle(
              style: theme.textTheme.labelLarge!.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
              child: label!,
            ),
          ],
        ),
      );
    }
    return LiquidGlassCard(
      layer: GlassLayer.secondary,
      onTap: wrapped,
      borderRadius: _size / 2,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Center(child: child),
      ),
    );
  }
}
