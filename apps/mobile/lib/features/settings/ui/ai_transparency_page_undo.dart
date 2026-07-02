part of 'ai_transparency_page.dart';

/// Pending-undo section. Lists every persisted entry in [DriftUndoStack]
/// and exposes per-row undo buttons. Tapping dispatches through the shared
/// persisted undo seam.
class _UndoSection extends ConsumerWidget {
  const _UndoSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(undoEntriesStreamProvider);
    final entries = entriesAsync.value ?? const <PersistedUndoEntry>[];
    final now = DateTime.now().toUtc();
    final live = entries
        .where(
          (e) =>
              e.showGlobalBanner &&
              (e.expiresAt == null || e.expiresAt!.isAfter(now)),
        )
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.s4,
              bottom: AppSpacing.s8,
            ),
            child: Text(
              l10n.aiTransparencyUndoSectionTitle,
              style: context.mutedLabelStyle,
            ),
          ),
          if (live.isEmpty)
            SoftCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
                vertical: AppSpacing.s14,
              ),
              child: Text(
                l10n.aiTransparencyUndoEmpty,
                style: context.captionStyle,
              ),
            )
          else
            SoftCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < live.length; i++) ...<Widget>[
                    if (i > 0) const FDivider(),
                    _UndoRow(entry: live[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _UndoRow extends ConsumerWidget {
  const _UndoRow({required this.entry});

  final PersistedUndoEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final summary =
        entry.payload['summary_zh'] as String? ??
        entry.payload['summaryZh'] as String? ??
        entry.kind;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        children: <Widget>[
          const AiSparkle(),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  summary,
                  style: context.theme.typography.body.sm.copyWith(
                    color: colors.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.expiresAt != null)
                  Text(entry.kind, style: context.captionStyle),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          AiPill(
            label: l10n.aiTransparencyUndoAction,
            state: AiPillState.selected,
            onTap: () async {
              final dispatcher = ref.read(persistedUndoDispatcherProvider);
              if (dispatcher == null) return;
              await dispatcher.undo(entry.token);
            },
          ),
        ],
      ),
    );
  }
}
