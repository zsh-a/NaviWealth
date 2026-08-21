part of 'home_page.dart';

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.snapshotAsync});

  final AsyncValue<DashboardSnapshot> snapshotAsync;

  @override
  Widget build(BuildContext context) =>
      _DashboardBodyContent(snapshotAsync: snapshotAsync);
}

class _DashboardBodyContent extends ConsumerWidget {
  const _DashboardBodyContent({required this.snapshotAsync});

  final AsyncValue<DashboardSnapshot> snapshotAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = snapshotAsync.value;
    final amountsHidden = ref.watch(financeAmountsHiddenProvider);
    final activation = ref.watch(financeActivationProvider).value;
    final importConfirmed = ref.watch(financeImportConfirmedProvider);
    final activationDismissed = ref.watch(financeActivationDismissedProvider);
    final agentResults = ref.watch(
      finance_agent_providers.latestFinanceAgentResultsProvider,
    );
    final showActivation =
        !activationDismissed && activation != null && !activation.isComplete;
    final showAgentResults =
        (agentResults.hasError && !agentResults.hasValue) ||
        agentResults.value?.visibleEntries.isNotEmpty == true;
    final hasEstablishedData =
        snapshot?.isEmpty == false ||
        activation?.hasLedgerData == true ||
        importConfirmed;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final basePadding = Breakpoints.isMobile(width)
            ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
                vertical: AppSpacing.s8,
              )
            : const EdgeInsets.symmetric(
                horizontal: AppSpacing.s24,
                vertical: AppSpacing.s16,
              );
        final padding = basePadding.copyWith(
          bottom:
              basePadding.bottom +
              MediaQuery.paddingOf(context).bottom +
              AppSpacing.s16,
        );

        Future<void> onRefresh() async {
          final sync = await ref.read(syncSchedulerProvider.future);
          final prices = await ref.read(priceSyncCoordinatorProvider.future);
          await Future.wait<void>([
            if (sync != null) sync.triggerNow(),
            prices.triggerNow(reason: PriceSyncReason.manual),
          ]);
          ref.invalidate(dashboardSnapshotProvider);
          ref.invalidate(dashboardDailyChangeProvider);
          ref.invalidate(dashboardHeaderMetricsProvider);
          await ref.read(dashboardSnapshotProvider.future);
        }

        Widget stickyNetWorth(BuildContext context, double progress) {
          final currentSnapshot = snapshot!;
          final l10n = AppLocalizations.of(context);
          return AppCollapsedSummaryBar(
            progress: progress,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.homeNetWorthTitle,
                    style: context.mutedLabelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                MoneyText(
                  amount: currentSnapshot.netWorth.amount.toDouble(),
                  currencyCode: currentSnapshot.baseCurrency,
                  compact: true,
                  style: TypographyTokens.numericTitleStrong,
                ),
              ],
            ),
          );
        }

        return AmountPrivacyScope(
          hidden: amountsHidden,
          child: BriefScaffold(
            padding: padding,
            maxContentWidth: !hasEstablishedData
                ? AdaptiveMaxWidth.narrow
                : AdaptiveMaxWidth.dashboard,
            onRefresh: onRefresh,
            greeting: const HomeGreetingHeader(),
            stage: snapshot != null
                ? _NetWorthHeader(snapshot: snapshot)
                : snapshotAsync.when(
                    loading: () => const _NetWorthStageSkeleton(),
                    error: (error, stackTrace) => _NetWorthStageError(
                      error: error,
                      stackTrace: stackTrace,
                      onRetry: () => ref.invalidate(dashboardSnapshotProvider),
                    ),
                    data: (value) => _NetWorthHeader(snapshot: value),
                  ),
            stickyBuilder: snapshot == null ? null : stickyNetWorth,
            modules: [
              _HomeSummaryLayout(
                showActivation: showActivation,
                showAgentResults: showAgentResults,
                quickActionMode: hasEstablishedData
                    ? HomeQuickActionMode.active
                    : HomeQuickActionMode.onboarding,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NetWorthStageSkeleton extends StatelessWidget {
  const _NetWorthStageSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppCollapsingStage(
      child: SkeletonCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 88, height: 14, radius: AppRadius.sm),
            SizedBox(height: AppSpacing.s12),
            SkeletonBox(width: 220, height: 42, radius: AppRadius.sm),
            SizedBox(height: AppSpacing.s12),
            SkeletonBox(width: 132, height: 14, radius: AppRadius.sm),
          ],
        ),
      ),
    );
  }
}

class _NetWorthStageError extends StatelessWidget {
  const _NetWorthStageError({
    required this.error,
    required this.stackTrace,
    required this.onRetry,
  });

  final Object error;
  final StackTrace stackTrace;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCollapsingStage(
      child: SoftCard.hero(
        padding: AppPageRhythm.heroPadding,
        child: kDefaultError(context, error, stackTrace, onRetry: onRetry),
      ),
    );
  }
}

class _HomeSummaryLayout extends ConsumerWidget {
  const _HomeSummaryLayout({
    required this.showActivation,
    required this.showAgentResults,
    required this.quickActionMode,
  });

  final bool showActivation;
  final bool showAgentResults;
  final HomeQuickActionMode quickActionMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasActivity =
        ref.watch(activityFeedPreviewProvider).value?.entries.isNotEmpty ==
        true;
    final hasInbox =
        ref.watch(financialInboxProvider).value?.isNotEmpty == true;
    final runway = ref.watch(moneyRunwayProvider).value;
    final runwayNeedsAttention =
        runway?.hasData == true && runway?.status != MoneyRunwayStatus.healthy;
    final primary = showActivation
        ? const FinanceActivationCard()
        : HomeQuickActions(mode: quickActionMode);
    final ordered = <AdaptiveSummaryTile>[
      AdaptiveSummaryTile(
        role: AdaptiveSummaryTileRole.featured,
        child: primary,
      ),
      if (hasInbox)
        const AdaptiveSummaryTile(
          role: AdaptiveSummaryTileRole.supporting,
          child: FinancialInboxCard(),
        ),
      if (runwayNeedsAttention)
        const AdaptiveSummaryTile(
          role: AdaptiveSummaryTileRole.supporting,
          child: MoneyRunwayCard(),
        ),
      if (showAgentResults)
        const AdaptiveSummaryTile(
          role: AdaptiveSummaryTileRole.featured,
          child: FinanceAgentResultsPanel(showPlaceholderStates: false),
        ),
      if (hasActivity)
        const AdaptiveSummaryTile(
          role: AdaptiveSummaryTileRole.continuous,
          child: ActivityTimelinePreview(),
        ),
    ];
    return AdaptiveSummaryGrid(items: ordered);
  }
}

class FinanceAgentResultsPanel extends ConsumerWidget {
  const FinanceAgentResultsPanel({
    super.key,
    this.showPlaceholderStates = true,
  });

  final bool showPlaceholderStates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(
      finance_agent_providers.latestFinanceAgentResultsProvider,
    );
    return AgentResultsPanel(
      resultsAsync: resultsAsync,
      showPlaceholderStates: showPlaceholderStates,
      bottomGap: AppSpacing.s20,
      onReload: () => ref.invalidate(
        finance_agent_providers.latestFinanceAgentResultsProvider,
      ),
      onOpen: (artifact) =>
          context.push(AgentArtifactRoutes.detail(artifact.id)),
      onRunAgain: (agentId) async {
        final controller = await ref.read(agentRunControllerProvider.future);
        await controller.runOnceById(agentId);
        ref.invalidate(
          finance_agent_providers.latestFinanceAgentResultsProvider,
        );
      },
    );
  }
}
