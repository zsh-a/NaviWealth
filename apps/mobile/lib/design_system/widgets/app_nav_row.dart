import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_badge.dart';
import 'app_tappable.dart';

/// Canonical tappable navigation row: icon slot + title + optional subtitle +
/// chevron. Replaces the per-feature copies of the same row chrome.
///
/// Two icon treatments:
///
/// * default — plain centred icon in a 36px slot; tone defaults to the muted
///   foreground;
/// * [AppNavRow.tinted] — tonal 40px tile for grouped destination lists
///   (Wealth objects); tone defaults to the brand primary.
///
/// [trailing] renders between the text and the chevron (e.g. a status
/// [AppBadge]); set [showChevron] to false when the row is not navigable.
class AppNavRow extends StatelessWidget {
  const AppNavRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.tone,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.s8),
    this.titleMaxLines,
    this.subtitleMaxLines,
    this.showChevron = true,
    this.semanticsLabel,
  }) : _tinted = false,
       _chevronSize = AppIconSizes.sm;

  /// Destination row with a tonal icon tile (grouped navigation lists).
  const AppNavRow.tinted({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.tone,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.s14,
      vertical: AppSpacing.s12,
    ),
    this.titleMaxLines,
    this.subtitleMaxLines = 1,
    this.showChevron = true,
    this.semanticsLabel,
  }) : _tinted = true,
       _chevronSize = AppIconSizes.h18;

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Optional widget between the text column and the chevron.
  final Widget? trailing;

  /// Semantic accent for the icon. When null, plain rows use the muted
  /// foreground and tinted tiles use the brand primary.
  final AppBadgeTone? tone;

  /// Row content inset.
  final EdgeInsetsGeometry padding;

  /// Line clamp for the title / subtitle; null leaves the text unclamped.
  final int? titleMaxLines;
  final int? subtitleMaxLines;

  /// Trailing chevron for drill-in rows.
  final bool showChevron;

  /// Accessibility label. Defaults to `'<title>, <subtitle>'`.
  final String? semanticsLabel;

  final bool _tinted;
  final double _chevronSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    final iconColor = switch (tone) {
      final tone? => _toneForeground(context, tone),
      null => _tinted ? colors.primary : colors.mutedForeground,
    };

    return Semantics(
      button: true,
      label: semanticsLabel ?? (subtitle == null ? title : '$title, $subtitle'),
      excludeSemantics: true,
      child: AppTappable(
        onPress: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              SizedBox.square(
                dimension: _tinted ? AppSpacing.s40 : 36,
                child: _tinted
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: iconColor.withValues(
                            alpha: AppOpacity.whisper,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Icon(
                          icon,
                          size: AppIconSizes.md,
                          color: iconColor,
                        ),
                      )
                    : Icon(icon, size: AppIconSizes.sm, color: iconColor),
              ),
              SizedBox(width: _tinted ? AppSpacing.s12 : AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.labelStyle,
                      maxLines: titleMaxLines,
                      overflow: titleMaxLines == null
                          ? null
                          : TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        subtitle,
                        style: context.captionStyle,
                        maxLines: subtitleMaxLines,
                        overflow: subtitleMaxLines == null
                            ? null
                            : TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              if (trailing != null) ...[
                trailing,
                if (showChevron) const SizedBox(width: AppSpacing.s6),
              ],
              if (showChevron)
                Icon(
                  FLucideIcons.chevronRight,
                  size: _chevronSize,
                  color: colors.mutedForeground,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _toneForeground(BuildContext context, AppBadgeTone tone) {
    final colors = context.theme.colors;
    final status = context.appTheme.status;
    return switch (tone) {
      AppBadgeTone.neutral => colors.mutedForeground,
      AppBadgeTone.accent => colors.primary,
      AppBadgeTone.info => status.info.fg,
      AppBadgeTone.success => status.success.fg,
      AppBadgeTone.warning => status.warning.fg,
      AppBadgeTone.error => status.danger.fg,
    };
  }
}
