part of 'home_page.dart';

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentArtifactCount =
        ref
            .watch(finance_agent_providers.latestFinanceAgentArtifactsProvider)
            .value
            ?.length ??
        0;
    return _DashboardBodyContent(
      snapshot: snapshot,
      agentArtifactCount: agentArtifactCount,
    );
  }
}

class _DashboardBodyContent extends ConsumerWidget {
  const _DashboardBodyContent({
    required this.snapshot,
    required this.agentArtifactCount,
  });

  final DashboardSnapshot snapshot;
  final int agentArtifactCount;

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
                        HomeGreetingHeader(
                          agentArtifactCount: agentArtifactCount,
                        ),
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
                    secondary: const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FinanceAgentResultsPanel(),
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
                        HomeGreetingHeader(
                          agentArtifactCount: agentArtifactCount,
                        ),
                        _NetWorthHeader(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s12),
                        const _HomeQuickActions(),
                        const FinanceAgentResultsPanel(),
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
    final artifactsAsync = ref.watch(
      finance_agent_providers.latestFinanceAgentArtifactsProvider,
    );
    if (artifactsAsync.isLoading && !artifactsAsync.hasValue) {
      return const _FinanceAgentPanelStateCard.loading();
    }
    if (artifactsAsync.hasError && !artifactsAsync.hasValue) {
      return _FinanceAgentPanelStateCard.error(
        error: artifactsAsync.error!,
        onRetry: () => ref.invalidate(
          finance_agent_providers.latestFinanceAgentArtifactsProvider,
        ),
      );
    }

    final artifacts = artifactsAsync.value ?? const <AgentArtifact>[];
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

    final runAsync = ref.watch(
      finance_agent_providers.latestWeeklyWealthReviewRunProvider,
    );
    if (runAsync.isLoading && !runAsync.hasValue) {
      return const _FinanceAgentPanelStateCard.loading();
    }
    if (runAsync.hasError && !runAsync.hasValue) {
      return _FinanceAgentPanelStateCard.error(
        error: runAsync.error!,
        onRetry: () => ref.invalidate(
          finance_agent_providers.latestWeeklyWealthReviewRunProvider,
        ),
      );
    }

    final run = runAsync.value;
    if (run == null) return const _FinanceAgentPanelStateCard.empty();
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
        finance_agent_providers.latestFinanceAgentArtifactsProvider,
      ),
    );
  }
}

class _FinanceAgentPanelStateCard extends StatelessWidget {
  const _FinanceAgentPanelStateCard._({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  const _FinanceAgentPanelStateCard.loading()
    : this._(
        icon: FLucideIcons.loaderCircle,
        title: _FinanceAgentPanelStateTitle.loading,
        message: _FinanceAgentPanelStateMessage.loading,
        loading: true,
      );

  const _FinanceAgentPanelStateCard.empty()
    : this._(
        icon: FLucideIcons.sparkles,
        title: _FinanceAgentPanelStateTitle.empty,
        message: _FinanceAgentPanelStateMessage.empty,
      );

  const _FinanceAgentPanelStateCard.error({
    required Object error,
    required VoidCallback onRetry,
  }) : this._(
         icon: FLucideIcons.triangleAlert,
         title: _FinanceAgentPanelStateTitle.error,
         message: _FinanceAgentPanelStateMessage.error,
         error: error,
         onRetry: onRetry,
       );

  final IconData icon;
  final _FinanceAgentPanelStateTitle title;
  final _FinanceAgentPanelStateMessage message;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final sem = SemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    final accent = error == null ? colors.primary : sem.danger;
    final resolvedTitle = switch (title) {
      _FinanceAgentPanelStateTitle.loading => l10n.financeAgentResultsLoading,
      _FinanceAgentPanelStateTitle.empty => l10n.financeAgentResultsEmptyTitle,
      _FinanceAgentPanelStateTitle.error => l10n.financeAgentResultsErrorTitle,
    };
    final resolvedMessage = switch (message) {
      _FinanceAgentPanelStateMessage.loading =>
        l10n.financeAgentResultsLoadingBody,
      _FinanceAgentPanelStateMessage.empty => l10n.financeAgentResultsEmptyBody,
      _FinanceAgentPanelStateMessage.error => l10n.financeAgentResultsErrorBody(
        '$error',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          level: SoftCardLevel.flat,
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIconTile(
                icon: icon,
                color: accent,
                size: 36,
                iconSize: AppIconSizes.h18,
                backgroundOpacity: AppOpacity.subtle,
                foregroundOpacity: 1,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(resolvedTitle, style: context.labelStyle),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      resolvedMessage,
                      style: context.captionStyle.copyWith(height: 1.4),
                    ),
                    if (loading) ...[
                      const SizedBox(height: AppSpacing.s12),
                      const FCircularProgress(
                        size: FCircularProgressSizeVariant.sm,
                      ),
                    ] else if (onRetry != null) ...[
                      const SizedBox(height: AppSpacing.s12),
                      AppQuietButton(
                        label: l10n.commonRetry,
                        onPress: onRetry,
                        prefix: const Icon(
                          FLucideIcons.refreshCw,
                          size: AppIconSizes.xs,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s20),
      ],
    );
  }
}

enum _FinanceAgentPanelStateTitle { loading, empty, error }

enum _FinanceAgentPanelStateMessage { loading, empty, error }

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
