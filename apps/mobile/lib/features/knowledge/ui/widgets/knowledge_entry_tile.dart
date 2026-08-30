import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';

/// Shared compact row for Notes and Decisions across KnowledgeOS surfaces.
class KnowledgeEntryTile extends StatelessWidget {
  const KnowledgeEntryTile({
    super.key,
    required this.title,
    required this.kindLabel,
    required this.icon,
    required this.onPress,
    this.subtitle,
    this.meta,
    this.tags = const <String>[],
    this.accented = false,
  });

  final String title;
  final String kindLabel;
  final IconData icon;
  final VoidCallback onPress;
  final String? subtitle;
  final String? meta;
  final List<String> tags;
  final bool accented;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final secondary = subtitle?.trim();
    final metadata = meta?.trim();
    final visibleTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return SoftCard.flat(
      onPress: onPress,
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: (accented ? colors.primary : colors.muted).withValues(
                alpha: accented ? AppOpacity.whisper : AppOpacity.prominent,
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: SizedBox.square(
              dimension: AppControlHeights.touchTarget,
              child: Icon(
                icon,
                size: AppIconSizes.sm,
                color: accented ? colors.primary : colors.mutedForeground,
              ),
            ),
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
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.rowTitleStyle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    FBadge(child: Text(kindLabel)),
                  ],
                ),
                if (secondary != null && secondary.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    secondary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.bodyCaptionStyle,
                  ),
                ],
                if (metadata != null && metadata.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s6),
                  Text(metadata, style: context.captionMediumStyle),
                ],
                if (visibleTags.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Wrap(
                    spacing: AppSpacing.s4,
                    runSpacing: AppSpacing.s4,
                    children: [
                      for (final tag in visibleTags.take(3))
                        AppBadge(
                          label: tag,
                          size: AppBadgeSize.compact,
                          outlined: true,
                        ),
                      if (visibleTags.length > 3)
                        AppBadge(
                          label: '+${visibleTags.length - 3}',
                          size: AppBadgeSize.compact,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s12),
            child: Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.sm,
              color: colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
