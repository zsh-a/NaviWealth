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
        // The wide cockpit assumes there is meaningful primary content to
        // balance its secondary rail. During first use that column is empty,
        // so keep the onboarding journey in a focused single-column flow.
        final useCockpit =
            width >= Breakpoints.contentTwoColumn && !snapshot.isEmpty;
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
          child: useCockpit
              ? RefreshIndicator(
                  onRefresh: onRefresh,
                  child: AppAtmosphere(
                    child: AppCollapsingScrollHost(
                      padding: EdgeInsets.fromLTRB(
                        padding.left,
                        AppSpacing.s4,
                        padding.right,
                        0,
                      ),
                      stickyBuilder: stickyNetWorth,
                      // Dual-column: primary and secondary scroll independently
                      // so the right rail stays usable on tall dashboards.
                      body: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AdaptiveMaxWidth.dashboard,
                          ),
                          child: Padding(
                            padding: padding.copyWith(top: AppSpacing.s0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    children: [
                                      const HomeGreetingHeader(),
                                      _NetWorthHeader(snapshot: snapshot),
                                      const SizedBox(
                                        height: AppPageRhythm.module,
                                      ),
                                      HomeQuickActions(
                                        mode: snapshot.isEmpty
                                            ? HomeQuickActionMode.onboarding
                                            : HomeQuickActionMode.active,
                                      ),
                                      const SizedBox(
                                        height: AppPageRhythm.section,
                                      ),
                                      const FinancialInboxCard(),
                                      const SizedBox(
                                        height: AppPageRhythm.section,
                                      ),
                                      const FinanceAgentResultsPanel(
                                        showPlaceholderStates: false,
                                      ),
                                      const SizedBox(
                                        height: AppPageRhythm.section,
                                      ),
                                      const ActivityTimelinePreview(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.s24),
                                SizedBox(
                                  width: kAdaptiveRightRailWidth,
                                  child: ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    children: const [
                                      MoneyRunwayCard(),
                                      SizedBox(height: AppPageRhythm.section),
                                      CashflowCalendarCard(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : BriefScaffold(
                  padding: padding,
                  maxContentWidth: snapshot.isEmpty
                      ? AdaptiveMaxWidth.narrow
                      : null,
                  onRefresh: onRefresh,
                  greeting: const HomeGreetingHeader(),
                  stage: _NetWorthHeader(snapshot: snapshot),
                  stickyBuilder: stickyNetWorth,
                  modules: [
                    const FinanceActivationCard(),
                    HomeQuickActions(
                      mode: snapshot.isEmpty
                          ? HomeQuickActionMode.onboarding
                          : HomeQuickActionMode.active,
                    ),
                    const FinancialInboxCard(),
                    const FinanceAgentResultsPanel(
                      showPlaceholderStates: false,
                    ),
                    const ActivityTimelinePreview(),
                  ],
                  // Cash-flow detail lives on its own page; Activity is
                  // the daily signal on Today.
                  secondary: const [MoneyRunwayCard(), CashflowCalendarCard()],
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
    if (bundle == null || bundle.visibleEntries.isEmpty) {
      if (!showPlaceholderStates) return const SizedBox.shrink();
      return _FinanceAgentPanelFrame(
        child: AgentResultPanelStateCard(
          icon: FLucideIcons.sparkles,
          title: l10n.financeAgentResultsEmptyTitle,
          message: l10n.financeAgentResultsEmptyBody,
        ),
      );
    }

    return _FinanceAgentPanelFrame(
      child: AgentResultsSection(
        bundle: bundle,
        metaLabelBuilder: (at) => _financeAgentMetaLabel(context, ref, at),
        onOpen: (artifact) =>
            context.push(AgentArtifactRoutes.detail(artifact.id)),
        onRetry: (agentId) async {
          final controller = await ref.read(agentRunControllerProvider.future);
          await controller.runOnceById(agentId);
          ref.invalidate(
            finance_agent_providers.latestFinanceAgentResultsProvider,
          );
        },
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

String _financeAgentMetaLabel(
  BuildContext context,
  WidgetRef ref,
  DateTime at,
) {
  final formatters = context.formatters(ref);
  return formatters.date(at.toLocal());
}
