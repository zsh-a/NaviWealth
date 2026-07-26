part of 'income_planner_page.dart';

enum _PlannerTab { opportunities, journal }

class _ConfiguredBody extends ConsumerStatefulWidget {
  const _ConfiguredBody({required this.profile});

  final OptionsStrategyProfile profile;

  @override
  ConsumerState<_ConfiguredBody> createState() => _ConfiguredBodyState();
}

class _ConfiguredBodyState extends ConsumerState<_ConfiguredBody> {
  _PlannerTab _tab = _PlannerTab.opportunities;
  bool _approvedOpen = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final approvedAsync = ref.watch(approvedUnderlyingsProvider);
    final scanState = ref.watch(scanControllerProvider);
    final cacheState = ref.watch(latestScanStateProvider);
    final opportunitiesAsync = ref.watch(cachedOpportunitiesProvider);
    final journalAsync = ref.watch(tradeJournalEntriesProvider);
    final approvedCount = approvedAsync.value?.length ?? 0;
    final opportunityCount = opportunitiesAsync.value?.length ?? 0;
    final openCount =
        journalAsync.value
            ?.where((entry) => entry.status == TradeJournalStatus.open)
            .length ??
        0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s32,
      ),
      children: [
        _PlannerOverviewCard(
          profile: widget.profile,
          approvedCount: approvedCount,
          opportunityCount: opportunityCount,
          openCount: openCount,
          scanState: scanState,
          cacheState: cacheState.value,
          onRefresh: () => _runScan(context),
          onManageUnderlyings: () => setState(() {
            _tab = _PlannerTab.opportunities;
            _approvedOpen = true;
          }),
        ),
        const SizedBox(height: AppSpacing.s16),
        SegmentedRow<_PlannerTab>(
          options: _PlannerTab.values,
          value: _tab,
          labelOf: (tab) => switch (tab) {
            _PlannerTab.opportunities =>
              l10n.incomePlannerWorkspaceOpportunities,
            _PlannerTab.journal => l10n.incomePlannerWorkspaceJournal,
          },
          iconOf: (tab) => switch (tab) {
            _PlannerTab.opportunities => FLucideIcons.scanSearch,
            _PlannerTab.journal => FLucideIcons.notebookPen,
          },
          onChanged: (tab) => setState(() => _tab = tab),
        ),
        const SizedBox(height: AppSpacing.s16),
        switch (_tab) {
          _PlannerTab.opportunities => _opportunitiesTab(
            context,
            approvedAsync: approvedAsync,
            scanState: scanState,
            cacheState: cacheState.value,
            opportunitiesAsync: opportunitiesAsync,
          ),
          _PlannerTab.journal => const _TradeJournalSection(),
        },
      ],
    );
  }

  Widget _opportunitiesTab(
    BuildContext context, {
    required AsyncValue<List<ApprovedUnderlying>> approvedAsync,
    required ScanState scanState,
    required ScanCacheState? cacheState,
    required AsyncValue<List<OptionsOpportunity>> opportunitiesAsync,
  }) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDisclosureHeader(
          title: l10n.incomePlannerApprovedSectionTitle,
          subtitle: approvedAsync.when(
            loading: () => l10n.planStatusLoading,
            error: (_, _) => l10n.commonLoadFailed,
            data: (items) => l10n.incomePlannerApprovedSummary(items.length),
          ),
          expanded: _approvedOpen,
          onToggle: () => setState(() => _approvedOpen = !_approvedOpen),
        ),
        AnimatedSizeFade(
          visible: _approvedOpen,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: FButton(
                    variant: FButtonVariant.outline,
                    onPress: () => showIncomeStrategyPlanSheet(context),
                    child: Text(l10n.incomePlannerAddApprovedCta),
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                approvedAsync.when(
                  loading: () => const _LoadingTile(),
                  error: (error, _) => AppEmptyState.error(
                    title: l10n.commonLoadFailed,
                    message: userSafeErrorMessage(context, error),
                    retryLabel: l10n.commonRetry,
                    onRetry: () => ref.invalidate(approvedUnderlyingsProvider),
                  ),
                  data: (items) => items.isEmpty
                      ? const _ApprovedEmpty()
                      : _ApprovedList(items: items),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        _OpportunitiesHeader(
          state: scanState,
          cacheState: cacheState,
          onRefresh: () => _runScan(context),
        ),
        const SizedBox(height: AppSpacing.s8),
        _OpportunitiesBody(
          state: scanState,
          opportunitiesAsync: opportunitiesAsync,
        ),
      ],
    );
  }

  Future<void> _runScan(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref.read(scanControllerProvider.notifier).runScan();
    if (!context.mounted || result == null) return;
    if (result.opportunities.isNotEmpty) {
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.incomePlannerScanCompletedToast(result.opportunities.length),
      );
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

class _PlannerOverviewCard extends ConsumerWidget {
  const _PlannerOverviewCard({
    required this.profile,
    required this.approvedCount,
    required this.opportunityCount,
    required this.openCount,
    required this.scanState,
    required this.cacheState,
    required this.onRefresh,
    required this.onManageUnderlyings,
  });

  final OptionsStrategyProfile profile;
  final int approvedCount;
  final int opportunityCount;
  final int openCount;
  final ScanState scanState;
  final ScanCacheState? cacheState;
  final VoidCallback onRefresh;
  final VoidCallback onManageUnderlyings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final running = scanState is ScanRunning;
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _profileSummary(l10n, formatters, profile, cacheState),
                  style: context.bodyCaptionStyle,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppBadge(
                label: optionsStrategyModeLabel(l10n, profile.mode),
                tone: AppBadgeTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          AppMetricCluster(
            dense: true,
            items: [
              AppMetricItem(
                label: l10n.incomePlannerWorkspaceCandidates,
                value: '$opportunityCount',
              ),
              AppMetricItem(
                label: l10n.incomePlannerWorkspaceOpenPositions,
                value: '$openCount',
              ),
              AppMetricItem(
                label: l10n.incomePlannerWorkspaceApproved,
                value: '$approvedCount',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              FButton(
                onPress: running ? null : onRefresh,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (running)
                      const Padding(
                        padding: EdgeInsets.only(right: AppSpacing.s8),
                        child: SizedBox.square(
                          dimension: AppIconSizes.sm,
                          child: FCircularProgress(),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(right: AppSpacing.s8),
                        child: Icon(
                          FLucideIcons.scanSearch,
                          size: AppIconSizes.sm,
                        ),
                      ),
                    Text(
                      running
                          ? l10n.incomePlannerRefreshRunning
                          : l10n.incomePlannerRefreshAction,
                    ),
                  ],
                ),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: onManageUnderlyings,
                child: Text(l10n.incomePlannerManageApprovedAction),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.push(FinanceRoutes.planWheel),
                child: Text(l10n.planWheelTitle),
              ),
            ],
          ),
          if (running) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              l10n.incomePlannerScanProgressHint,
              style: context.captionStyle,
            ),
          ],
        ],
      ),
    );
  }

  String _profileSummary(
    AppLocalizations l10n,
    AppFormatters formatters,
    OptionsStrategyProfile profile,
    ScanCacheState? cache,
  ) {
    final scan = cache == null
        ? l10n.incomePlannerWorkspaceNeverScanned
        : cache.isStale
        ? l10n.incomePlannerWorkspaceScanStale
        : l10n.incomePlannerWorkspaceScanFresh;
    return l10n.incomePlannerWorkspaceProfileSummary(
      profile.minDte,
      profile.maxDte,
      formatters.percent(
        profile.maxCapitalPerTradePct.toDouble(),
        decimalDigits: 0,
      ),
      scan,
    );
  }
}

int _daysUntil(DateTime date) =>
    date.toUtc().difference(DateTime.now().toUtc()).inDays;
