import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/semantic_colors.dart';
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
    final verticalPadding = switch (size) {
      AppBadgeSize.compact => AppSpacing.s2,
      AppBadgeSize.regular => AppSpacing.s4,
    };
    final textStyle = switch (size) {
      AppBadgeSize.compact => context.compactBadgeLabelStyle,
      AppBadgeSize.regular => context.badgeLabelStyle,
    };
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth ?? 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: container,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: outlined || borderColor != null
              ? Border.all(color: borderColor ?? colors.border)
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: verticalPadding,
          ),
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
    final semantic = SemanticColors.of(context);
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
        foreground: semantic.onInfoContainer,
        container: semantic.infoContainer,
      ),
      AppBadgeTone.success => _BadgePalette(
        foreground: semantic.onSuccessContainer,
        container: semantic.successContainer,
      ),
      AppBadgeTone.warning => _BadgePalette(
        foreground: semantic.onWarningContainer,
        container: semantic.warningContainer,
      ),
      AppBadgeTone.error => _BadgePalette(
        foreground: semantic.onDangerContainer,
        container: semantic.dangerContainer,
      ),
    };
  }
}
