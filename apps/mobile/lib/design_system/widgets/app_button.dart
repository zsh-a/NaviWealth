import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';
import '../tokens/spacing_tokens.dart';

/// Button variant.
enum AppButtonVariant { primary, secondary, tertiary }

/// Custom button variants that replace Material's ElevatedButton /
/// FilledButton / OutlinedButton / TextButton with a Stripe-inspired
/// compact style.
///
/// Usage:
/// ```dart
/// AppButton.primary(label: 'Save', onPressed: () {})
/// AppButton.secondary(label: 'Cancel', onPressed: () {})
/// AppButton.tertiary(label: 'Learn more', onPressed: () {})
/// ```
class AppButton extends StatelessWidget {
  const AppButton._({
    super.key,
    required this.label,
    required this.variant,
    this.icon,
    this.onPressed,
    this.compact = false,
  });

  /// Filled emerald button — primary action.
  const AppButton.primary({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onPressed,
    bool compact = false,
  }) : this._(
          key: key,
          label: label,
          variant: AppButtonVariant.primary,
          icon: icon,
          onPressed: onPressed,
          compact: compact,
        );

  /// Outlined hairline button — secondary action, no fill.
  const AppButton.secondary({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onPressed,
    bool compact = false,
  }) : this._(
          key: key,
          label: label,
          variant: AppButtonVariant.secondary,
          icon: icon,
          onPressed: onPressed,
          compact: compact,
        );

  /// Text-only button — tertiary action, hover highlight only.
  const AppButton.tertiary({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onPressed,
    bool compact = false,
  }) : this._(
          key: key,
          label: label,
          variant: AppButtonVariant.tertiary,
          icon: icon,
          onPressed: onPressed,
          compact: compact,
        );

  final String label;
  final AppButtonVariant variant;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool compact;

  static const double _height = 36;
  static const double _heightCompact = 32;
  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final h = compact ? _heightCompact : _height;
    final textStyle = theme.textTheme.labelLarge;

    final foregroundColor = switch (variant) {
      AppButtonVariant.primary => cs.onPrimary,
      AppButtonVariant.secondary => cs.onSurface,
      AppButtonVariant.tertiary => cs.onSurface,
    };

    final disabledColor = cs.onSurface.withValues(alpha: 0.38);

    Widget labelWidget = Text(
      label,
      style: textStyle?.copyWith(color: onPressed != null ? foregroundColor : disabledColor),
    );

    if (icon != null) {
      labelWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _iconSize, color: onPressed != null ? foregroundColor : disabledColor),
          const SizedBox(width: Spacing.s6),
          labelWidget,
        ],
      );
    }

    final padding = EdgeInsets.symmetric(
      horizontal: compact ? Spacing.s12 : Spacing.s16,
      vertical: compact ? Spacing.s6 : Spacing.s8,
    );

    final isHovered = ValueNotifier(false);
    final isPressed = ValueNotifier(false);

    return ValueListenableBuilder2<bool, bool>(
      first: isHovered,
      second: isPressed,
      builder: (context, hovered, pressed, child) {
        final overlayAlpha = pressed ? 0.08 : (hovered ? 0.04 : 0.0);
        final overlayColor = (isDark ? Colors.white : Colors.black).withValues(alpha: overlayAlpha);

        Color bgColor;
        switch (variant) {
          case AppButtonVariant.primary:
            bgColor = ColorPalette.green600;
          case AppButtonVariant.secondary:
            bgColor = overlayColor;
          case AppButtonVariant.tertiary:
            bgColor = overlayColor;
        }

        return Focus(
          child: Semantics(
            button: true,
            label: label,
            child: MouseRegion(
              onEnter: (_) => isHovered.value = true,
              onExit: (_) => isHovered.value = false,
              child: GestureDetector(
                onTapDown: (_) => isPressed.value = true,
                onTapUp: (_) => isPressed.value = false,
                onTapCancel: () => isPressed.value = false,
                onTap: onPressed,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: h,
                  padding: padding,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: variant == AppButtonVariant.secondary
                        ? Border.all(color: cs.outline)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: DefaultTextStyle(
                    style: textStyle?.copyWith(
                          color: onPressed != null ? foregroundColor : disabledColor,
                        ) ??
                        const TextStyle(),
                    child: icon != null
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: _iconSize, color: onPressed != null ? foregroundColor : disabledColor),
                              const SizedBox(width: Spacing.s6),
                              Text(label),
                            ],
                          )
                        : Text(label),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Helper that listens to two ValueListenables and rebuilds.
class ValueListenableBuilder2<A, B> extends StatelessWidget {
  const ValueListenableBuilder2({
    super.key,
    required this.first,
    required this.second,
    required this.builder,
    this.child,
  });

  final ValueNotifier<A> first;
  final ValueNotifier<B> second;
  final Widget Function(BuildContext, A, B, Widget?) builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: first,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: second,
          builder: (context, b, _) {
            return builder(context, a, b, child);
          },
        );
      },
    );
  }
}
