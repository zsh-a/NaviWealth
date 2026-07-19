part of 'sessions_panel.dart';

/// Compact history row — typography-first, no card chrome.
///
/// Inspired by ChatGPT / Claude sidebars: title + one quiet preview line,
/// time on the trailing edge, overflow only. Selected state is a soft fill
/// without borders / icon wells / accent rails.
class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onTogglePin,
    required this.onToggleArchive,
  });

  final ChatSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleArchive;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final lastAt = session.lastMessageAt ?? session.createdAt;
    final preview = _previewText(session.preview);
    final title = _displayTitle(session.title, preview);

    final tile = FTappable(
      onPress: onTap,
      child: AnimatedContainer(
        duration: AppMotionPolicy.duration(context, Motion.fast),
        curve: Motion.standardDecelerate,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s12,
          AppSpacing.s10,
          AppSpacing.s4,
          AppSpacing.s10,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: AppOpacity.subtle)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (session.pinned) ...[
                        Icon(
                          FLucideIcons.pin,
                          size: 12,
                          color: colors.primary.withValues(
                            alpha: AppOpacity.strong,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s4),
                      ],
                      if (session.archived) ...[
                        Icon(
                          FLucideIcons.archive,
                          size: 12,
                          color: colors.mutedForeground,
                        ),
                        const SizedBox(width: AppSpacing.s4),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (selected
                                      ? context.labelStyle
                                      : context.mediumLabelStyle)
                                  .copyWith(color: colors.foreground),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Text(
                        _formatRelative(l10n, lastAt),
                        style: context.microCaptionStyle.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.captionStyle.copyWith(
                        color: colors.mutedForeground,
                        height: 1.35,
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
                  icon: session.pinned ? FLucideIcons.pinOff : FLucideIcons.pin,
                  title: session.pinned
                      ? l10n.aiChatSessionUnpinAction
                      : l10n.aiChatSessionPinAction,
                  onPress: onTogglePin,
                ),
                AppAdaptiveAction(
                  icon: session.archived
                      ? FLucideIcons.archiveRestore
                      : FLucideIcons.archive,
                  title: session.archived
                      ? l10n.aiChatSessionUnarchiveAction
                      : l10n.aiChatSessionArchiveAction,
                  onPress: onToggleArchive,
                ),
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
                      size: AppIconSizes.sm,
                      color: colors.mutedForeground.withValues(
                        alpha: AppOpacity.strong,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('session-${session.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
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

/// Prefer a clean title; if still the default placeholder and we have a
/// preview, surface the preview as the title instead of "新对话".
String _displayTitle(String title, String? preview) {
  final t = title.trim();
  if (t.isEmpty || t == '新对话' || t == 'New chat' || t == 'New conversation') {
    if (preview != null && preview.isNotEmpty) {
      return preview.length <= 40 ? preview : '${preview.substring(0, 40)}…';
    }
  }
  return t;
}

/// Collapse whitespace and strip common markdown so history previews
/// read as prose, not source.
String? _previewText(String? raw) {
  if (raw == null) return null;
  var text = raw;
  // Fenced code blocks → drop.
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  // Inline code backticks.
  text = text.replaceAll('`', '');
  // ATX headings.
  text = text.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
  // Bold / italic markers.
  text = text.replaceAll(RegExp(r'(\*\*|__|\*|_|~~)'), '');
  // List markers.
  text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
  // Blockquote.
  text = text.replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '');
  // Links [label](url) → label.
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (m) => m.group(1) ?? '',
  );
  // Images ![alt](url) → alt.
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
    (m) => m.group(1) ?? '',
  );
  // Tables / pipes noise.
  text = text.replaceAll('|', ' ');
  // Collapse whitespace.
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;
  if (text.length <= 72) return text;
  return '${text.substring(0, 72)}…';
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
