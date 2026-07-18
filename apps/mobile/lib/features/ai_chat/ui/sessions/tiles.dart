part of 'sessions_panel.dart';

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ChatSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final lastAt = session.lastMessageAt ?? session.createdAt;
    final preview = _previewText(session.preview);
    final tile = ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
      child: AnimatedContainer(
        duration: AppMotionPolicy.duration(context, Motion.fast),
        curve: Motion.standardDecelerate,
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: AppOpacity.subtle)
              : colors.background,
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.scrim)
                : colors.border.withValues(alpha: AppOpacity.scrim),
            width: AppStroke.hairline,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
        child: FTappable(
          onPress: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: AppSpacing.s4,
                  height: AppSpacing.s40,
                  margin: const EdgeInsets.only(top: AppSpacing.s2),
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : Colors.transparent,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppRadius.sm),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Container(
                  width: AppSpacing.s32,
                  height: AppSpacing.s32,
                  margin: const EdgeInsets.only(top: AppSpacing.s2),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primary.withValues(alpha: AppOpacity.subtle)
                        : colors.muted.withValues(alpha: AppOpacity.prominent),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    FLucideIcons.messageCircle,
                    size: AppIconSizes.sm,
                    color: selected ? colors.primary : colors.mutedForeground,
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
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: selected
                                  ? context.labelStyle.copyWith(
                                      color: colors.foreground,
                                    )
                                  : context.mediumLabelStyle.copyWith(
                                      color: colors.foreground,
                                    ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s8),
                          Text(
                            _formatRelative(l10n, lastAt),
                            style: context.microCaptionStyle,
                          ),
                        ],
                      ),
                      if (preview != null) ...[
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.captionStyle.copyWith(
                            color: colors.mutedForeground,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (session.messageCount > 0) ...[
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          l10n.aiChatSessionMessageCount(session.messageCount),
                          style: context.microCaptionStyle.copyWith(
                            color: colors.mutedForeground.withValues(
                              alpha: AppOpacity.strong,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AppAdaptiveActionMenu(
                  title: l10n.aiChatSessionActionsTitle,
                  actions: <AppAdaptiveAction>[
                    AppAdaptiveAction(
                      icon: FLucideIcons.pencil,
                      title: l10n.aiChatSessionRenameAction,
                      onPress: onRename,
                    ),
                    AppAdaptiveAction(
                      icon: FLucideIcons.trash2,
                      title: l10n.commonDelete,
                      destructive: true,
                      onPress: onDelete,
                    ),
                  ],
                  triggerBuilder: (context, openMenu, focusNode) => Focus(
                    focusNode: focusNode,
                    child: FTooltip(
                      tipBuilder: (_, _) => Text(l10n.aiChatSessionMoreTooltip),
                      child: FButton.icon(
                        variant: FButtonVariant.ghost,
                        onPress: openMenu,
                        child: Icon(
                          FLucideIcons.ellipsis,
                          size: AppIconSizes.h18,
                          color: colors.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Swipe-to-delete on touch platforms; desktop keeps the overflow menu.
    return Dismissible(
      key: ValueKey('session-${session.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        // Delete flow is confirm-gated; never auto-dismiss the tile here.
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.s16),
        decoration: BoxDecoration(
          color: colors.destructive.withValues(alpha: AppOpacity.subtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(
          FLucideIcons.trash2,
          size: AppIconSizes.h18,
          color: colors.destructive,
        ),
      ),
      child: tile,
    );
  }
}

String? _previewText(String? raw) {
  if (raw == null) return null;
  final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return null;
  if (collapsed.length <= 120) return collapsed;
  return '${collapsed.substring(0, 120)}…';
}

String _formatRelative(AppLocalizations l10n, DateTime when) =>
    AppFormatters.relativeTime(
      when,
      justNow: l10n.aiChatRelativeJustNow,
      minutesAgo: l10n.aiChatRelativeMinutesAgo,
      hoursAgo: l10n.aiChatRelativeHoursAgo,
      daysAgo: l10n.aiChatRelativeDaysAgo,
      dateFallback: (d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}',
    );
