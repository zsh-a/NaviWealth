import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_icon_button.dart';
import 'app_icon_tile.dart';
import 'app_interaction.dart';
import 'soft_card.dart';

/// One row on the cross-domain life timeline (Phase G presentation).
@immutable
class LifeTimelineItem {
  const LifeTimelineItem({
    required this.id,
    required this.at,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.onOpen,
    this.onAction,
    this.actionLabel,
    this.domainLabel,
  }) : assert(
         onAction == null || actionLabel != null,
         'actionLabel is required when onAction is provided',
       );

  final String id;
  final DateTime at;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onOpen;
  final VoidCallback? onAction;
  final String? actionLabel;
  final String? domainLabel;
}

/// Vertical cross-domain activity stream.
class LifeTimeline extends StatelessWidget {
  const LifeTimeline({
    super.key,
    required this.items,
    this.empty,
    this.timeLabel,
  });

  final List<LifeTimelineItem> items;
  final Widget? empty;
  final String Function(DateTime at)? timeLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return empty ?? const SizedBox.shrink();
    }
    final colors = context.theme.colors;
    return SoftCard.raised(
      padding: AppPageRhythm.cardPadding,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppPageRhythm.row,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: AppSpacing.s14),
                    Container(
                      width: AppStroke.hairline,
                      height: AppSpacing.s12,
                      color: colors.border.withValues(
                        alpha: AppOpacity.highlight,
                      ),
                    ),
                  ],
                ),
              ),
            _LifeTimelineRow(
              item: items[i],
              timeLabel: timeLabel?.call(items[i].at),
            ),
          ],
        ],
      ),
    );
  }
}

class _LifeTimelineRow extends StatelessWidget {
  const _LifeTimelineRow({required this.item, this.timeLabel});

  final LifeTimelineItem item;
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIconTile(
          icon: item.icon,
          color: item.accent,
          size: 30,
          iconSize: AppIconSizes.sm,
          radius: AppRadius.sm,
          backgroundOpacity: AppOpacity.subtle,
          foregroundOpacity: 1,
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: context.rowTitleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (timeLabel != null)
                    Text(timeLabel!, style: context.microCaptionStyle),
                ],
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                item.subtitle,
                style: context.captionStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.domainLabel != null) ...[
                const SizedBox(height: AppSpacing.s4),
                Text(
                  item.domainLabel!,
                  style: context.microLabelStyle.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (item.onOpen != null)
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.h18,
            color: colors.mutedForeground.withValues(
              alpha: AppOpacity.disabled,
            ),
          ),
      ],
    );

    final primary = item.onOpen == null
        ? content
        : Semantics(
            button: true,
            child: FTappable(
              onPress: AppInteraction.wrap(
                item.onOpen,
                intent: AppInteractionIntent.navigate,
              ),
              child: content,
            ),
          );
    final action = item.onAction;
    if (action == null) return primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: primary),
        const SizedBox(width: AppSpacing.s8),
        AppIconButton(
          icon: FLucideIcons.listTodo,
          tooltip: item.actionLabel!,
          onPress: AppInteraction.wrap(
            action,
            intent: AppInteractionIntent.reveal,
          ),
          size: 36,
          iconSize: AppIconSizes.xs,
          iconColor: colors.mutedForeground,
          surface: AppIconButtonSurface.softMuted,
        ),
      ],
    );
  }
}
