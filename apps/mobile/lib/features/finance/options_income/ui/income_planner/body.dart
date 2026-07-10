part of 'income_planner_page.dart';

class _ConfiguredBody extends ConsumerWidget {
  const _ConfiguredBody({required this.profile});

  final OptionsStrategyProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final approvedAsync = ref.watch(approvedUnderlyingsProvider);
    final scanState = ref.watch(scanControllerProvider);
    final cacheState = ref.watch(latestScanStateProvider);
    final opportunitiesAsync = ref.watch(cachedOpportunitiesProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        SectionHeader(
          title: l10n.incomePlannerApprovedSectionTitle,
          trailing: FButton(
            variant: FButtonVariant.outline,
            onPress: () => showApprovedUnderlyingSheet(context),
            child: Text(l10n.incomePlannerAddApprovedCta),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        approvedAsync.when(
          loading: () => const _LoadingTile(),
          error: (e, _) => AppEmptyState.error(
            title: l10n.commonLoadFailed,
            message: '$e',
            action: FButton(
              variant: FButtonVariant.ghost,
              onPress: () => ref.invalidate(approvedUnderlyingsProvider),
              child: Text(l10n.commonRetry),
            ),
          ),
          data: (items) => items.isEmpty
              ? const _ApprovedEmpty()
              : _ApprovedList(items: items),
        ),
        const SizedBox(height: AppSpacing.s24),
        _OpportunitiesHeader(
          state: scanState,
          cacheState: cacheState.value,
          onRefresh: () => _runScan(context, ref),
        ),
        const SizedBox(height: AppSpacing.s8),
        _OpportunitiesBody(
          state: scanState,
          opportunitiesAsync: opportunitiesAsync,
        ),
        const SizedBox(height: AppSpacing.s24),
        const _TradeJournalSection(),
      ],
    );
  }

  Future<void> _runScan(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(scanControllerProvider.notifier);
    final result = await controller.runScan();
    if (!context.mounted || result == null || result.opportunities.isNotEmpty) {
      return;
    }
    AppMessenger.show(
      context,
      ToastKind.warning,
      result.universe.isEmpty
          ? l10n.incomePlannerRefreshUniverseEmpty
          : l10n.incomePlannerScanNoMatchesToast,
      duration: const Duration(seconds: 5),
    );
  }
}

class _OpportunitiesHeader extends StatelessWidget {
  const _OpportunitiesHeader({
    required this.state,
    required this.cacheState,
    required this.onRefresh,
  });

  final ScanState state;
  final ScanCacheState? cacheState;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final running = state is ScanRunning;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.incomePlannerOpportunitiesSectionTitle,
                style: context.titleLabelStyle,
              ),
              if (cacheState != null) ...[
                const SizedBox(height: AppSpacing.s2),
                Text(
                  _formatLastScan(l10n, cacheState!),
                  style: context.captionStyle.copyWith(
                    color: cacheState!.isStale
                        ? context.theme.colors.destructive
                        : context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.primary,
          onPress: running ? null : onRefresh,
          child: Text(
            running
                ? l10n.incomePlannerRefreshRunning
                : l10n.incomePlannerRefreshAction,
          ),
        ),
      ],
    );
  }

  String _formatLastScan(AppLocalizations l10n, ScanCacheState s) {
    final delta = DateTime.now().toUtc().difference(s.scannedAt);
    final ago = delta.inMinutes < 60
        ? l10n.incomePlannerLastScanMinutes(delta.inMinutes)
        : delta.inHours < 24
        ? l10n.incomePlannerLastScanHours(delta.inHours)
        : l10n.incomePlannerLastScanDays(delta.inDays);
    if (s.isStale) {
      return l10n.incomePlannerLastScanStaleSummary(
        l10n.incomePlannerLastScanLabel,
        ago,
        l10n.incomePlannerLastScanStale,
      );
    }
    return l10n.incomePlannerLastScanFresh(
      l10n.incomePlannerLastScanLabel,
      ago,
      s.count,
    );
  }
}

class _OpportunitiesBody extends StatelessWidget {
  const _OpportunitiesBody({
    required this.state,
    required this.opportunitiesAsync,
  });

  final ScanState state;
  final AsyncValue<List<OptionsOpportunity>> opportunitiesAsync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state is ScanFailure) {
      return _ErrorCard(
        title: l10n.incomePlannerRefreshFailedTitle,
        message: userSafeErrorMessage(context, (state as ScanFailure).error),
      );
    }
    return opportunitiesAsync.when(
      loading: () => const _LoadingTile(),
      error: (e, _) => _ErrorCard(
        title: l10n.incomePlannerRefreshFailedTitle,
        message: '$e',
      ),
      data: (items) {
        if (items.isEmpty) {
          if (state is ScanSuccess) {
            return _ScanEmptyResultCard(result: (state as ScanSuccess).result);
          }
          return _EmptyCard(body: l10n.incomePlannerOpportunitiesEmpty);
        }
        return Column(
          children: [
            for (final opp in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                child: _OpportunityCard(opportunity: opp),
              ),
          ],
        );
      },
    );
  }
}
