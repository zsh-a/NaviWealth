import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_grouped_action_list.dart';

/// One row in a bottom-sheet action list.
///
/// Title-only actions stay compact; descriptive actions opt into a second
/// line through [subtitle]. The sheet itself owns the surface, so rows remain
/// flat instead of creating a nested card inside the modal.
class AppActionSheetTile extends StatelessWidget {
  const AppActionSheetTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onPress,
    this.showChevron = true,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onPress;
  final bool showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final subtitle = this.subtitle;
    final hasSubtitle = subtitle != null && subtitle.isNotEmpty;
    final foreground = destructive ? colors.destructive : colors.foreground;
    final accent = destructive ? colors.destructive : colors.primary;
    return Semantics(
      button: true,
      label: title,
      child: FTappable(
        onPress: onPress,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: hasSubtitle ? AppSpacing.s10 : AppSpacing.s12,
          ),
          child: Row(
            children: [
              Container(
                width: AppSpacing.s28,
                height: AppSpacing.s28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: AppOpacity.faint),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: AppIconSizes.sm, color: accent),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.labelStyle.copyWith(color: foreground),
                    ),
                    if (hasSubtitle) ...[
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.captionStyle,
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron) ...[
                const SizedBox(width: AppSpacing.s10),
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.sm,
                  color: colors.mutedForeground.withValues(
                    alpha: AppOpacity.disabled,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Groups [AppActionSheetTile]s with quiet inset dividers. The containing
/// [AppSheetSurface] is the only elevated surface.
class AppActionSheetList extends StatelessWidget {
  const AppActionSheetList({super.key, required this.children});

  final List<AppActionSheetTile> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1) const AppGroupedDivider(),
        ],
      ],
    );
  }
}
