part of 'home_page.dart';

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return DeferredProviderSnapshot<List<InsightItem>>(
      provider: dashboardInsightsProvider,
      initialValue: const <InsightItem>[],
      builder: (context, insights) =>
          _DashboardBodyContent(snapshot: snapshot, insights: insights),
    );
  }
}

class _DashboardBodyContent extends ConsumerWidget {
  const _DashboardBodyContent({required this.snapshot, required this.insights});

  final DashboardSnapshot snapshot;
  final List<InsightItem> insights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amountsHidden = ref.watch(_financeAmountsHiddenProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final useCockpit = width >= Breakpoints.contentTwoColumn;
        final basePadding = Breakpoints.isMobile(width)
            ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
                vertical: AppSpacing.s16,
              )
            : const EdgeInsets.symmetric(
                horizontal: AppSpacing.s24,
                vertical: AppSpacing.s24,
              );
        final padding = basePadding.copyWith(
          bottom:
              basePadding.bottom +
              MediaQuery.paddingOf(context).bottom +
              AppSpacing.s16,
        );

        return AmountPrivacyScope(
          hidden: amountsHidden,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dashboardSnapshotProvider);
              ref.invalidate(dashboardHeaderMetricsProvider);
              await ref.read(dashboardSnapshotProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                if (useCockpit)
                  AdaptiveContentFrame(
                    maxWidth: AdaptiveMaxWidth.dashboard,
                    layout: AdaptiveFrameLayout.cockpit,
                    padding: padding.copyWith(top: 0),
                    header: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HomeGreetingHeader(insightCount: insights.length),
                        _NetWorthHeader(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s12),
                        const _HomeQuickActions(),
                      ],
                    ),
                    primary: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AllocationSummary(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s20),
                        const _CashFlowCardsGrid(),
                        const SizedBox(height: AppSpacing.s20),
                        const TrendCard(),
                      ],
                    ),
                    secondary: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const FinanceAgentResultsPanel(),
                        if (insights.isNotEmpty) ...[
                          AiInsightFeed(insights: insights),
                          const SizedBox(height: AppSpacing.s20),
                        ],
                        const ActivityTimelinePreview(),
                      ],
                    ),
                  )
                else
                  AdaptiveContentFrame(
                    maxWidth: AdaptiveMaxWidth.narrow,
                    padding: padding.copyWith(top: 0),
                    primary: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HomeGreetingHeader(insightCount: insights.length),
                        _NetWorthHeader(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s12),
                        const _HomeQuickActions(),
                        const FinanceAgentResultsPanel(),
                        if (insights.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.s20),
                          AiInsightFeed(insights: insights),
                        ],
                        const SizedBox(height: AppSpacing.s20),
                        AllocationSummary(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s20),
                        const _CashFlowCardsGrid(),
                        const SizedBox(height: AppSpacing.s20),
                        const TrendCard(),
                        const SizedBox(height: AppSpacing.s20),
                        const ActivityTimelinePreview(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class FinanceAgentResultsPanel extends ConsumerWidget {
  const FinanceAgentResultsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artifacts = ref
        .watch(finance_agent_providers.latestFinanceAgentArtifactsProvider)
        .value;
    if (artifacts != null && artifacts.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final artifact in artifacts) ...[
            AgentResultCard(
              artifact: artifact,
              metaLabel: _financeAgentMetaLabel(
                context,
                ref,
                artifact.createdAt,
              ),
              onOpen: () => showAgentArtifactSheet(
                context: context,
                artifact: artifact,
                subtitle: _financeAgentMetaLabel(
                  context,
                  ref,
                  artifact.createdAt,
                ),
                onVisibilityChanged: () => ref.invalidate(
                  finance_agent_providers.latestFinanceAgentArtifactsProvider,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          const SizedBox(height: AppSpacing.s20),
        ],
      );
    }

    final run = ref
        .watch(finance_agent_providers.latestWeeklyWealthReviewRunProvider)
        .value;
    if (run == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgentRunStatusCard(
          record: run,
          metaLabel: _financeAgentMetaLabel(context, ref, run.startedAt),
          onRetry: () async {
            final controller = await ref.read(
              agentRunControllerProvider.future,
            );
            await controller.runOnceById(kWeeklyWealthReviewAgentId);
            ref.invalidate(
              finance_agent_providers.latestFinanceAgentArtifactsProvider,
            );
            ref.invalidate(
              finance_agent_providers.latestWeeklyWealthReviewArtifactProvider,
            );
            ref.invalidate(
              finance_agent_providers.latestWeeklyWealthReviewRunProvider,
            );
          },
        ),
        const SizedBox(height: AppSpacing.s20),
      ],
    );
  }
}

class _CashFlowCardsGrid extends StatelessWidget {
  const _CashFlowCardsGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= Breakpoints.mobile;
        if (!twoColumns) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PassiveIncomeCard(),
              SizedBox(height: AppSpacing.s12),
              CashflowCalendarCard(),
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: PassiveIncomeCard()),
            SizedBox(width: AppSpacing.s12),
            Expanded(child: CashflowCalendarCard()),
          ],
        );
      },
    );
  }
}

String _financeAgentMetaLabel(
  BuildContext context,
  WidgetRef ref,
  DateTime at,
) {
  final formatters = context.formatters(ref);
  return 'FinanceOS · ${formatters.date(at.toLocal())}';
}
