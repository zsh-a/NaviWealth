import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';

enum AppBadgeTone { neutral, accent, info, success, warning, error }

enum AppBadgeSize { compact, regular }

/// Canonical pill badge for short status labels across domains.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.size = AppBadgeSize.regular,
    this.icon,
    this.outlined = false,
    this.foregroundColor,
    this.containerColor,
    this.borderColor,
    this.minWidth,
  });

  final String label;
  final AppBadgeTone tone;
  final AppBadgeSize size;
  final IconData? icon;
  final bool outlined;
  final Color? foregroundColor;
  final Color? containerColor;
  final Color? borderColor;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final palette = _BadgePalette.resolve(context, tone);
    final foreground = foregroundColor ?? palette.foreground;
    final container = containerColor ?? palette.container;
    final spec = context.appTheme.badge;
    final textStyle = switch (size) {
      AppBadgeSize.compact => context.compactBadgeLabelStyle,
      AppBadgeSize.regular => context.badgeLabelStyle,
    };
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth ?? 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: container,
          borderRadius: BorderRadius.circular(spec.radius),
          border: outlined || borderColor != null
              ? Border.all(color: borderColor ?? colors.border)
              : null,
        ),
        child: Padding(
          padding: switch (size) {
            AppBadgeSize.compact => spec.compactPadding,
            AppBadgeSize.regular => spec.regularPadding,
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: minWidth == null
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppIconSizes.xs, color: foreground),
                const SizedBox(width: AppSpacing.s4),
              ],
              Flexible(
                child: Text(
                  label,
                  style: textStyle.copyWith(color: foreground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgePalette {
  const _BadgePalette({required this.foreground, required this.container});

  final Color foreground;
  final Color container;

  static _BadgePalette resolve(BuildContext context, AppBadgeTone tone) {
    final colors = context.theme.colors;
    final status = context.appTheme.status;
    return switch (tone) {
      AppBadgeTone.neutral => _BadgePalette(
        foreground: colors.mutedForeground,
        container: colors.muted,
      ),
      AppBadgeTone.accent => _BadgePalette(
        foreground: colors.primary,
        container: colors.primary.withValues(alpha: AppOpacity.subtle),
      ),
      // Status badges pair the container with its on-container foreground —
      // the bare status color on a tinted fill lands well below WCAG AA
      // (info was 1.92:1 in light mode). See theme_contrast_test.dart.
      AppBadgeTone.info => _BadgePalette(
        foreground: status.info.onContainer,
        container: status.info.container,
      ),
      AppBadgeTone.success => _BadgePalette(
        foreground: status.success.onContainer,
        container: status.success.container,
      ),
      AppBadgeTone.warning => _BadgePalette(
        foreground: status.warning.onContainer,
        container: status.warning.container,
      ),
      AppBadgeTone.error => _BadgePalette(
        foreground: status.danger.onContainer,
        container: status.danger.container,
      ),
    };
  }
}
