part of 'home_page.dart';

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) =>
      _DashboardBodyContent(snapshot: snapshot);
}

class _DashboardBodyContent extends ConsumerWidget {
  const _DashboardBodyContent({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = this.snapshot;
    final amountsHidden = ref.watch(_financeAmountsHiddenProvider);
    final activation = ref.watch(financeActivationProvider).value;
    final activationDismissed = ref.watch(financeActivationDismissedProvider);
    final agentResults = ref.watch(
      finance_agent_providers.latestFinanceAgentResultsProvider,
    );
    final showActivation =
        !activationDismissed && activation != null && !activation.isComplete;
    final showAgentResults =
        (agentResults.hasError && !agentResults.hasValue) ||
        agentResults.value?.visibleEntries.isNotEmpty == true;
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
          ref.invalidate(dashboardHeaderMetricsProvider);
          await ref.read(dashboardSnapshotProvider.future);
        }

        Widget stickyNetWorth(BuildContext context, double progress) {
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
                  amount: snapshot.netWorth.amount.toDouble(),
                  currencyCode: snapshot.baseCurrency,
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
            maxContentWidth: snapshot.isEmpty
                ? AdaptiveMaxWidth.narrow
                : AdaptiveMaxWidth.dashboard,
            onRefresh: onRefresh,
            greeting: const HomeGreetingHeader(),
            stage: _NetWorthHeader(snapshot: snapshot),
            stickyBuilder: stickyNetWorth,
            summaryTiles: [
              if (showActivation)
                const AdaptiveSummaryTile(child: FinanceActivationCard()),
              AdaptiveSummaryTile(
                role: AdaptiveSummaryTileRole.featured,
                child: HomeQuickActions(
                  mode: snapshot.isEmpty
                      ? HomeQuickActionMode.onboarding
                      : HomeQuickActionMode.active,
                ),
              ),
              const AdaptiveSummaryTile(child: FinancialInboxCard()),
              if (showAgentResults)
                const AdaptiveSummaryTile(
                  child: FinanceAgentResultsPanel(showPlaceholderStates: false),
                ),
              const AdaptiveSummaryTile(child: ActivityTimelinePreview()),
              const AdaptiveSummaryTile(child: MoneyRunwayCard()),
              const AdaptiveSummaryTile(child: CashflowCalendarCard()),
            ],
          ),
        );
      },
    );
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
