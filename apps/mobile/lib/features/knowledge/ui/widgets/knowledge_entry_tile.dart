import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/knowledge_models.dart';
import '../knowledge_decision_review_sheet.dart';

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
    this.iconColor,
    this.decisionStatus,
    this.menuActions = const <AppAdaptiveAction>[],
  });

  final String title;
  final String kindLabel;
  final IconData icon;
  final VoidCallback onPress;
  final String? subtitle;
  final String? meta;
  final List<String> tags;
  final bool accented;

  /// Optional tonal override for the leading [AppIconTile]. When null the
  /// tile keeps the muted treatment, or the KnowledgeOS domain accent when
  /// [accented].
  final Color? iconColor;

  /// When set, renders a compact status badge next to the kind badge so
  /// decisions are scannable in lists without opening the detail page.
  final DecisionStatus? decisionStatus;

  /// Overflow actions (e.g. delete) shown behind an adaptive menu trigger.
  /// When empty, the row renders only the navigation chevron.
  final List<AppAdaptiveAction> menuActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final secondary = subtitle?.trim();
    final metadata = meta?.trim();
    final visibleTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    // `accented` rows tint with the KnowledgeOS domain accent (indigo)
    // instead of the global primary; per-tile [iconColor] still wins so
    // notes and decisions can keep distinct treatments.
    final knowledgeAccent = DomainAccents.knowledge.resolve(
      context.appTheme.brightness,
    );
    final tileColor =
        iconColor ?? (accented ? knowledgeAccent : colors.mutedForeground);
    return SoftCard.flat(
      onPress: onPress,
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: icon,
            color: tileColor,
            size: AppControlHeights.touchTarget,
            iconSize: AppIconSizes.sm,
            radius: AppRadius.md,
            backgroundOpacity: accented || iconColor != null
                ? AppOpacity.whisper
                : AppOpacity.subtle,
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
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.rowTitleStyle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    FBadge(child: Text(kindLabel)),
                    if (decisionStatus case final status?) ...[
                      const SizedBox(width: AppSpacing.s4),
                      AppBadge(
                        label: knowledgeDecisionStatusLabel(l10n, status),
                        tone: _decisionStatusTone(status),
                        size: AppBadgeSize.compact,
                        icon: _decisionStatusIcon(status),
                      ),
                    ],
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
          if (menuActions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: AppAdaptiveActionMenu(
                title: title,
                actions: menuActions,
                triggerBuilder: (context, openMenu, focusNode) => Focus(
                  focusNode: focusNode,
                  child: AppIconButton(
                    icon: FLucideIcons.ellipsis,
                    tooltip: l10n.shellMoreActions,
                    onPress: openMenu,
                    size: 32,
                    iconSize: AppIconSizes.xs,
                    iconColor: colors.mutedForeground,
                    surface: AppIconButtonSurface.softMuted,
                  ),
                ),
              ),
            )
          else
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

/// Tone mapping follows the execution-domain precedent
/// (`ExecutionActionCard`): attention/overdue states read as warning/error.
AppBadgeTone _decisionStatusTone(DecisionStatus status) => switch (status) {
  DecisionStatus.draft => AppBadgeTone.neutral,
  DecisionStatus.active => AppBadgeTone.info,
  DecisionStatus.paused => AppBadgeTone.warning,
  DecisionStatus.expired => AppBadgeTone.warning,
  DecisionStatus.verified => AppBadgeTone.success,
  DecisionStatus.falsified => AppBadgeTone.error,
  DecisionStatus.superseded => AppBadgeTone.neutral,
};

IconData _decisionStatusIcon(DecisionStatus status) => switch (status) {
  DecisionStatus.draft => FLucideIcons.filePenLine,
  DecisionStatus.active => FLucideIcons.play,
  DecisionStatus.paused => FLucideIcons.pause,
  DecisionStatus.expired => FLucideIcons.clockAlert,
  DecisionStatus.verified => FLucideIcons.badgeCheck,
  DecisionStatus.falsified => FLucideIcons.badgeX,
  DecisionStatus.superseded => FLucideIcons.replace,
};
