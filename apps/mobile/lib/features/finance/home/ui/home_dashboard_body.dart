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
                        const HomeGreetingHeader(),
                        _NetWorthHeader(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s12),
                        HomeQuickActions(
                          mode: snapshot.isEmpty
                              ? HomeQuickActionMode.onboarding
                              : HomeQuickActionMode.active,
                        ),
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
                    secondary: const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FinanceAgentResultsPanel(showPlaceholderStates: false),
                        ActivityTimelinePreview(),
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
                        const HomeGreetingHeader(),
                        _NetWorthHeader(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s12),
                        HomeQuickActions(
                          mode: snapshot.isEmpty
                              ? HomeQuickActionMode.onboarding
                              : HomeQuickActionMode.active,
                        ),
                        const FinanceAgentResultsPanel(
                          showPlaceholderStates: false,
                        ),
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
    final l10n = AppLocalizations.of(context);
    if (resultsAsync.isLoading && !resultsAsync.hasValue) {
      if (!showPlaceholderStates) return const SizedBox.shrink();
      return _FinanceAgentPanelFrame(
        child: AgentResultPanelStateCard(
          icon: FLucideIcons.loaderCircle,
          title: l10n.financeAgentResultsLoading,
          message: l10n.financeAgentResultsLoadingBody,
          loading: true,
        ),
      );
    }
    if (resultsAsync.hasError && !resultsAsync.hasValue) {
      if (!showPlaceholderStates) return const SizedBox.shrink();
      return _FinanceAgentPanelFrame(
        child: AgentResultPanelStateCard(
          icon: FLucideIcons.triangleAlert,
          title: l10n.financeAgentResultsErrorTitle,
          message: userSafeErrorMessage(context, resultsAsync.error!),
          error: true,
          onRetry: () => ref.invalidate(
            finance_agent_providers.latestFinanceAgentResultsProvider,
          ),
        ),
      );
    }

    final bundle = resultsAsync.value;
    final runToShowBeforeArtifacts = bundle?.runToShowBeforeArtifacts;
    if (runToShowBeforeArtifacts != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentRunStatusCard(
            record: runToShowBeforeArtifacts,
            metaLabel: _financeAgentMetaLabel(
              context,
              ref,
              runToShowBeforeArtifacts.startedAt,
            ),
            onRetry: () async {
              final controller = await ref.read(
                agentRunControllerProvider.future,
              );
              await controller.runOnceById(runToShowBeforeArtifacts.agentId);
              ref.invalidate(
                finance_agent_providers.latestFinanceAgentResultsProvider,
              );
            },
          ),
          const SizedBox(height: AppSpacing.s20),
        ],
      );
    }

    final artifacts = bundle?.artifacts ?? const <AgentArtifact>[];
    if (artifacts.isNotEmpty) {
      final primary = artifacts.first;
      final secondary = artifacts.skip(1).toList(growable: false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentResultCard(
            artifact: primary,
            metaLabel: _financeAgentMetaLabel(context, ref, primary.createdAt),
            onOpen: () => _openFinanceAgentArtifact(context, ref, primary),
            layout: AgentResultCardLayout.summary,
          ),
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            for (var i = 0; i < secondary.length; i++) ...[
              AgentCompactResultRow(
                artifact: secondary[i],
                metaLabel: _financeAgentMetaLabel(
                  context,
                  ref,
                  secondary[i].createdAt,
                ),
                onOpen: () =>
                    _openFinanceAgentArtifact(context, ref, secondary[i]),
              ),
              if (i != secondary.length - 1)
                const SizedBox(height: AppSpacing.s6),
            ],
          ],
          const SizedBox(height: AppSpacing.s20),
        ],
      );
    }

    final run = bundle?.latestRun;
    if (run == null) {
      if (!showPlaceholderStates) return const SizedBox.shrink();
      return _FinanceAgentPanelFrame(
        child: AgentResultPanelStateCard(
          icon: FLucideIcons.sparkles,
          title: l10n.financeAgentResultsEmptyTitle,
          message: l10n.financeAgentResultsEmptyBody,
        ),
      );
    }
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
            await controller.runOnceById(run.agentId);
            ref.invalidate(
              finance_agent_providers.latestFinanceAgentResultsProvider,
            );
          },
        ),
        const SizedBox(height: AppSpacing.s20),
      ],
    );
  }

  void _openFinanceAgentArtifact(
    BuildContext context,
    WidgetRef ref,
    AgentArtifact artifact,
  ) {
    final metaLabel = _financeAgentMetaLabel(context, ref, artifact.createdAt);
    showAgentArtifactSheet(
      context: context,
      artifact: artifact,
      subtitle: metaLabel,
      onVisibilityChanged: () => ref.invalidate(
        finance_agent_providers.latestFinanceAgentResultsProvider,
      ),
    );
  }
}

class _FinanceAgentPanelFrame extends StatelessWidget {
  const _FinanceAgentPanelFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
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
