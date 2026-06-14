import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import 'app_icon_tile.dart';

/// Compact two-line chip for dense metric summaries.
///
/// Use when a card needs several small value/label pairs. For one-word status
/// tags use [AppBadge] instead.
class AppInfoChip extends StatelessWidget {
  const AppInfoChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppOpacity.light),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconTile(
              icon: icon,
              color: color,
              size: 22,
              iconSize: AppIconSizes.xs,
              radius: AppRadius.xs,
              backgroundOpacity: AppOpacity.whisper,
              foregroundOpacity: 1,
            ),
            const SizedBox(width: AppSpacing.s6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 144),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: typography.xs.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    label,
                    style: typography.xs.copyWith(
                      color: colors.mutedForeground,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
