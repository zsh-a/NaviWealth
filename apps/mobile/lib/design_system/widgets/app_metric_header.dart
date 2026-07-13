import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_icon_tile.dart';

/// Canonical header for tappable dashboard / metric modules.
///
/// Icon tile + muted title + optional chevron. Replaces the former
/// `DashboardCardHeader` and ad-hoc per-feature header rows.
class AppMetricHeader extends StatelessWidget {
  const AppMetricHeader({
    super.key,
    required this.icon,
    required this.title,
    this.color,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;

  /// Accent for the icon tile. Defaults to the brand primary.
  final Color? color;

  /// Trailing chevron for drill-in surfaces. Hide on non-navigable cards.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final accent = color ?? colors.primary;
    return Row(
      children: [
        AppIconTile(
          icon: icon,
          color: accent,
          size: 28,
          iconSize: AppIconSizes.sm,
          radius: AppRadius.sm,
          backgroundOpacity: AppOpacity.subtle,
          foregroundOpacity: AppOpacity.prominent,
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Text(
            title,
            style: context.mutedLabelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showChevron)
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.h18,
            color: colors.mutedForeground.withValues(
              alpha: AppOpacity.disabled,
            ),
          ),
      ],
    );
  }
}
