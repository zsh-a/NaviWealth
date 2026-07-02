part of 'sync_status_page.dart';

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.event,
    required this.cursor,
    required this.deviceId,
    required this.apiBaseUrl,
    required this.now,
  });

  final SyncStatusEvent event;
  final int? cursor;
  final String? deviceId;
  final String? apiBaseUrl;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      child: Column(
        children: [
          _Row(label: l10n.syncStatusDetailState, value: event.status.name),
          const FDivider(),
          _Row(
            label: l10n.syncStatusDetailUpdatedAt,
            value: _relativeTime(l10n, event.at, now),
          ),
          if (deviceId != null) ...[
            const FDivider(),
            _Row(
              label: l10n.syncStatusDetailDevice,
              value: _shortDeviceId(deviceId!),
              monospace: true,
            ),
          ],
          const FDivider(),
          _Row(
            label: l10n.syncStatusDetailCursor,
            value: (cursor == null || cursor == 0)
                ? l10n.syncStatusDetailCursorUnset
                : '#$cursor',
            monospace: cursor != null && cursor != 0,
          ),
          if (event.conflicts.remoteRows > 0) ...[
            const FDivider(),
            _Row(
              label: l10n.syncStatusDetailRemoteRows,
              value:
                  '${event.conflicts.appliedRows}/${event.conflicts.remoteRows}',
              monospace: true,
            ),
          ],
          if (apiBaseUrl != null) ...[
            const FDivider(),
            _Row(
              label: l10n.syncStatusDetailEndpoint,
              value: apiBaseUrl!,
              monospace: true,
              wrap: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _LocalCountsCard extends StatelessWidget {
  const _LocalCountsCard({required this.counts});

  final LocalTableCounts? counts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (counts == null) {
      return const SoftCard(
        padding: EdgeInsets.all(AppSpacing.s12),
        child: Center(child: FCircularProgress()),
      );
    }

    final countIds = counts!.keys.toList(growable: false);

    Widget cell(String id) {
      final value = counts![id] ?? 0;
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _localCountLabel(l10n, id),
                style: context.captionStyle,
              ),
            ),
            Text(
              '$value',
              style: context.bodyCaptionStyle.copyWith(
                color: value > 0
                    ? context.theme.colors.foreground
                    : context.theme.colors.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s12,
              AppSpacing.s8,
              AppSpacing.s12,
              AppSpacing.s4,
            ),
            child: Text(
              l10n.syncStatusLocalCountsHeader,
              style: context.captionStyle,
            ),
          ),
          for (var i = 0; i < countIds.length; i += 2)
            Row(
              children: [
                Expanded(child: cell(countIds[i])),
                Expanded(
                  child: i + 1 < countIds.length
                      ? cell(countIds[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _localCountLabel(AppLocalizations l10n, String id) => switch (id) {
  'accounts_user' => l10n.syncStatusLocalAccountsUser,
  'accounts_system' => l10n.syncStatusLocalAccountsSystem,
  'journal_entries' => l10n.syncStatusLocalJournalEntries,
  'postings' => l10n.syncStatusLocalPostings,
  'assets' => l10n.syncStatusLocalAssets,
  'prices' => l10n.syncStatusLocalPrices,
  'liabilities' => l10n.syncStatusLocalLiabilities,
  'tags' => l10n.syncStatusLocalTags,
  _ => id,
};
