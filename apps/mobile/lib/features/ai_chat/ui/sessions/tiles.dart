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
                      Radius.circular(AppRadius.xxs),
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
                FTooltip(
                  tipBuilder: (_, _) => Text(l10n.aiChatSessionMoreTooltip),
                  child: FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: () => _showActions(context, l10n),
                    child: Icon(
                      FLucideIcons.ellipsis,
                      size: AppIconSizes.h18,
                      color: colors.mutedForeground,
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

  Future<void> _showActions(BuildContext context, AppLocalizations l10n) {
    return showAppSheet<void>(
      context: context,
      title: l10n.aiChatSessionActionsTitle,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionRow(
            icon: FLucideIcons.pencil,
            label: l10n.aiChatSessionRenameAction,
            onTap: () {
              Navigator.of(ctx).pop();
              onRename();
            },
          ),
          const SizedBox(height: AppSpacing.s4),
          _ActionRow(
            icon: FLucideIcons.trash2,
            label: l10n.commonDelete,
            color: ctx.theme.colors.destructive,
            onTap: () {
              Navigator.of(ctx).pop();
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.theme.colors.foreground;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: FTappable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              Icon(icon, size: AppIconSizes.md, color: fg),
              const SizedBox(width: AppSpacing.s12),
              Text(
                label,
                style: context.theme.typography.body.md.copyWith(color: fg),
              ),
            ],
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
