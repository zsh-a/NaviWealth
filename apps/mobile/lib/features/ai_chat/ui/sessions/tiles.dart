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
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
      child: ColoredBox(
        color: selected
            ? colors.primary.withValues(alpha: AppOpacity.subtle)
            : Colors.transparent,
        child: FTappable(
          onPress: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s8,
            ),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.s4,
                  height: AppSpacing.s32,
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : Colors.transparent,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppRadius.sm),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Icon(
                  FLucideIcons.messageCircle,
                  size: AppIconSizes.h18,
                  color: selected ? colors.primary : colors.mutedForeground,
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
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
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        _formatRelative(l10n, lastAt),
                        style: context.microCaptionStyle,
                      ),
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
  }
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
