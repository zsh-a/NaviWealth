part of 'income_planner_page.dart';

enum _OpportunityFilter { all, put, call, leaps }

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
                        ? context.appTheme.status.warning.fg
                        : context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.outline,
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

  String _formatLastScan(AppLocalizations l10n, ScanCacheState state) {
    final delta = DateTime.now().toUtc().difference(state.scannedAt);
    final ago = delta.inMinutes < 60
        ? l10n.incomePlannerLastScanMinutes(delta.inMinutes)
        : delta.inHours < 24
        ? l10n.incomePlannerLastScanHours(delta.inHours)
        : l10n.incomePlannerLastScanDays(delta.inDays);
    if (state.isStale) {
      return l10n.incomePlannerLastScanStaleSummary(
        l10n.incomePlannerLastScanLabel,
        ago,
        l10n.incomePlannerLastScanStale,
      );
    }
    return l10n.incomePlannerLastScanFresh(
      l10n.incomePlannerLastScanLabel,
      ago,
      state.count,
    );
  }
}

class _OpportunitiesBody extends StatefulWidget {
  const _OpportunitiesBody({
    required this.state,
    required this.opportunitiesAsync,
    required this.onScan,
  });

  final ScanState state;
  final AsyncValue<List<OptionsOpportunity>> opportunitiesAsync;
  final VoidCallback onScan;

  @override
  State<_OpportunitiesBody> createState() => _OpportunitiesBodyState();
}

class _OpportunitiesBodyState extends State<_OpportunitiesBody> {
  _OpportunityFilter _filter = _OpportunityFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.state is ScanFailure) {
      return AppEmptyState.error(
        title: l10n.incomePlannerRefreshFailedTitle,
        message: userSafeErrorMessage(
          context,
          (widget.state as ScanFailure).error,
        ),
        compact: true,
      );
    }
    return widget.opportunitiesAsync.when(
      loading: () => const _LoadingTile(),
      error: (error, _) => AppEmptyState.error(
        title: l10n.incomePlannerRefreshFailedTitle,
        message: userSafeErrorMessage(context, error),
        compact: true,
      ),
      data: (items) {
        if (items.isEmpty) {
          if (widget.state is ScanSuccess) {
            return _ScanEmptyResultCard(
              result: (widget.state as ScanSuccess).result,
            );
          }
          return AppEmptyState(
            icon: FLucideIcons.scanSearch,
            title: l10n.incomePlannerOpportunitiesEmpty,
            compact: true,
            action: FButton(
              variant: FButtonVariant.outline,
              onPress: widget.onScan,
              prefix: const Icon(
                FLucideIcons.scanSearch,
                size: AppIconSizes.sm,
              ),
              child: Text(l10n.incomePlannerRefreshAction),
            ),
          );
        }
        final visible = items.where(_matchesFilter).toList()
          ..sort((a, b) => b.score.compareTo(a.score));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppAdaptiveChoice<_OpportunityFilter>(
              title: l10n.incomePlannerOpportunitiesSectionTitle,
              options: _OpportunityFilter.values,
              value: _filter,
              labelOf: (filter) => switch (filter) {
                _OpportunityFilter.all =>
                  l10n.incomePlannerOpportunityFilterAll,
                _OpportunityFilter.put => l10n.incomePlannerChipCashSecuredPut,
                _OpportunityFilter.call => l10n.incomePlannerChipCoveredCall,
                _OpportunityFilter.leaps => l10n.incomePlannerChipLeaps,
              },
              iconOf: (filter) => switch (filter) {
                _OpportunityFilter.all => FLucideIcons.layers,
                _OpportunityFilter.put => FLucideIcons.shieldCheck,
                _OpportunityFilter.call => FLucideIcons.badgeDollarSign,
                _OpportunityFilter.leaps => FLucideIcons.trendingUp,
              },
              onChanged: (filter) => setState(() => _filter = filter),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.incomePlannerOpportunityCountSummary(
                visible.length,
                items.length,
              ),
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s4),
            if (visible.isEmpty)
              // A lane can be empty even when the scan succeeded — show
              // that lane's rejection reasons instead of a mute shrug.
              widget.state is ScanSuccess
                  ? _ScanEmptyResultCard(
                      result: (widget.state as ScanSuccess).result,
                      lane: _laneStrategy,
                    )
                  : AppEmptyState(
                      icon: FLucideIcons.scanSearch,
                      title: l10n.incomePlannerOpportunityFilterEmpty,
                      compact: true,
                      action: FButton(
                        variant: FButtonVariant.outline,
                        onPress: () =>
                            setState(() => _filter = _OpportunityFilter.all),
                        child: Text(l10n.incomePlannerOpportunityFilterAll),
                      ),
                    )
            else
              ..._laneSections(context, l10n, visible),
          ],
        );
      },
    );
  }

  /// The "all" view keeps the two lanes apart: sell-side yield scores
  /// and LEAPS cost-efficiency scores are not comparable, so a merged
  /// sort would let LEAPS (typically 0.95+) bury every sell candidate.
  List<Widget> _laneSections(
    BuildContext context,
    AppLocalizations l10n,
    List<OptionsOpportunity> visible,
  ) {
    Widget card(OptionsOpportunity opportunity) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: _OpportunityCard(opportunity: opportunity),
    );
    if (_filter != _OpportunityFilter.all) {
      return [for (final opportunity in visible) card(opportunity)];
    }
    final sell = visible
        .where((o) => o.strategy != OpportunityStrategy.leapsCall)
        .toList(growable: false);
    final leaps = visible
        .where((o) => o.strategy == OpportunityStrategy.leapsCall)
        .toList(growable: false);
    if (sell.isEmpty || leaps.isEmpty) {
      return [for (final opportunity in visible) card(opportunity)];
    }
    Widget header(String title) => SectionHeader.module(title: title);
    return [
      header(l10n.incomePlannerLaneSellSection),
      for (final opportunity in sell) card(opportunity),
      header(l10n.incomePlannerLaneLeapsSection),
      for (final opportunity in leaps) card(opportunity),
    ];
  }

  OpportunityStrategy? get _laneStrategy => switch (_filter) {
    _OpportunityFilter.all => null,
    _OpportunityFilter.put => OpportunityStrategy.cashSecuredPut,
    _OpportunityFilter.call => OpportunityStrategy.coveredCall,
    _OpportunityFilter.leaps => OpportunityStrategy.leapsCall,
  };

  bool _matchesFilter(OptionsOpportunity opportunity) {
    final lane = _laneStrategy;
    return lane == null || opportunity.strategy == lane;
  }
}

class _OpportunityCard extends ConsumerWidget {
  const _OpportunityCard({required this.opportunity});

  final OptionsOpportunity opportunity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final colors = context.theme.colors;
    final contract = opportunity.contract;
    final metrics = opportunity.metrics;
    final expiry = MaterialLocalizations.of(context)
        .formatShortDate(contract.expiration.toLocal());
    return SoftCard.flat(
      onPress: () => showOpportunityDetailSheet(context, opportunity),
      borderRadius: AppRadius.lg,
      padding: AppPageRhythm.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contract.underlying, style: context.titleLabelStyle),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      l10n.incomePlannerOpportunityExpirySummary(
                        expiry,
                        contract.dte,
                      ),
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Wrap(
                spacing: AppSpacing.s6,
                runSpacing: AppSpacing.s4,
                alignment: WrapAlignment.end,
                children: [
                  AppBadge(
                    label: opportunityStrategyShortLabel(
                      l10n,
                      opportunity.strategy,
                    ),
                    tone: AppBadgeTone.accent,
                  ),
                  AppBadge(
                    label: _riskLabel(l10n, opportunity.risk),
                    tone: _riskTone(opportunity.risk),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
          AppMetricCluster(
            dense: true,
            items: switch (metrics) {
              final OpportunityMetrics sell => [
                AppMetricItem(
                  label: l10n.incomePlannerMetricPremiumTotal,
                  value: formatters.currency(
                    sell.premium.amount,
                    code: sell.premium.currency,
                  ),
                ),
                AppMetricItem(
                  label: l10n.incomePlannerMetricBreakeven,
                  value: formatters.currency(
                    sell.breakeven.amount,
                    code: sell.breakeven.currency,
                  ),
                ),
                AppMetricItem(
                  label: l10n.incomePlannerMetricAnnualized,
                  value: formatters.percent(
                    sell.annualizedYield.toDouble(),
                    decimalDigits: 1,
                  ),
                ),
              ],
              final LeapsOpportunityMetrics leaps => [
                AppMetricItem(
                  label: l10n.incomePlannerMetricLeapsCost,
                  value: formatters.currency(
                    leaps.totalCost.amount,
                    code: leaps.totalCost.currency,
                  ),
                ),
                AppMetricItem(
                  label: l10n.incomePlannerMetricBreakeven,
                  value: formatters.currency(
                    leaps.breakeven.amount,
                    code: leaps.breakeven.currency,
                  ),
                ),
                AppMetricItem(
                  label: l10n.incomePlannerMetricAnnualCost,
                  value: leaps.annualizedExtrinsicCostPct == null
                      ? '—'
                      : formatters.percent(
                          leaps.annualizedExtrinsicCostPct!.toDouble(),
                          decimalDigits: 1,
                        ),
                ),
              ],
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            opportunity.explanation.worstCase,
            style: context.bodyCaptionStyle.copyWith(height: 1.45),
          ),
          if (opportunity.explanation.whyGood.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  FLucideIcons.circleCheck,
                  size: AppIconSizes.sm,
                  color: colors.primary,
                ),
                const SizedBox(width: AppSpacing.s6),
                Expanded(
                  child: Text(
                    opportunity.explanation.whyGood.first,
                    style: context.captionStyle,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanEmptyResultCard extends ConsumerWidget {
  const _ScanEmptyResultCard({required this.result, this.lane});

  final ScanResult result;

  /// Scope the rejection summary to one scan lane (the selected filter
  /// chip); null summarises the whole batch.
  final OpportunityStrategy? lane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final universeEmpty = result.universe.isEmpty;
    final rejectedInLane = lane == null
        ? result.rejected
        : result.rejected
              .where((r) => r.strategy == null || r.strategy == lane)
              .toList(growable: false);
    final counts = <String, int>{};
    for (final rejected in rejectedInLane) {
      for (final reason in rejected.reasons) {
        counts.update(reason, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final topReasons = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SoftCard.flat(
      padding: AppPageRhythm.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.incomePlannerNoMatchesTitle, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(
            universeEmpty
                ? l10n.incomePlannerRefreshUniverseEmpty
                : l10n.incomePlannerOpportunitiesAllRejected,
            style: context.bodyCaptionStyle.copyWith(height: 1.45),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            l10n.incomePlannerScanSummary(
              result.universe.length,
              result.rejected.length,
              result.errors.length,
            ),
            style: context.captionStyle,
          ),
          if (topReasons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              l10n.incomePlannerRejectionReasonsTitle,
              style: context.captionLabelStyle,
            ),
            const SizedBox(height: AppSpacing.s4),
            for (final reason in topReasons.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s4),
                child: Text(
                  l10n.incomePlannerRejectionReasonSummary(
                    _rejectionReasonLabel(l10n, reason.key),
                    reason.value,
                  ),
                  style: context.captionStyle,
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => showStrategyProfileSheet(context),
                child: Text(l10n.incomePlannerPreferencesAction),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => showIncomeStrategyPlanSheet(context),
                child: Text(l10n.incomePlannerAddApprovedCta),
              ),
              if (lane == OpportunityStrategy.leapsCall)
                // The dominant LEAPS rejections (budget, delta band)
                // are fixed in the plan, not the profile — link there.
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => _openLeapsBudget(context, ref),
                  child: Text(l10n.incomePlannerAdjustLeapsBudget),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Route "adjust LEAPS budget" to the one LEAPS-enabled plan when it is
/// unambiguous, otherwise to the strategy page where the user picks the
/// underlying.
void _openLeapsBudget(BuildContext context, WidgetRef ref) {
  final plans = ref.read(incomeStrategyPlansProvider).value ?? const [];
  final leapsPlans = plans
      .where(
        (plan) =>
            plan.enabledSleeves.contains(IncomeStrategySleeveKind.leapsCall),
      )
      .toList(growable: false);
  if (leapsPlans.length == 1) {
    showIncomeStrategyPlanSheet(context, existing: leapsPlans.single);
  } else {
    context.push(FinanceRoutes.planIncome);
  }
}

String _riskLabel(AppLocalizations l10n, OpportunityRiskLevel risk) =>
    switch (risk) {
      OpportunityRiskLevel.low => l10n.incomePlannerRiskLow,
      OpportunityRiskLevel.moderate => l10n.incomePlannerRiskModerate,
      OpportunityRiskLevel.elevated => l10n.incomePlannerRiskElevated,
    };

AppBadgeTone _riskTone(OpportunityRiskLevel risk) => switch (risk) {
  OpportunityRiskLevel.low => AppBadgeTone.neutral,
  OpportunityRiskLevel.moderate => AppBadgeTone.neutral,
  OpportunityRiskLevel.elevated => AppBadgeTone.error,
};

String _rejectionReasonLabel(AppLocalizations l10n, String reason) =>
    switch (reason) {
      'cash_required_above_cap' => l10n.incomePlannerRejectCapitalLimit,
      'open_interest_below_minimum' ||
      'volume_below_minimum' => l10n.incomePlannerRejectLiquidity,
      'bid_ask_spread_above_maximum' => l10n.incomePlannerRejectSpread,
      'dte_outside_target_range' => l10n.incomePlannerRejectDte,
      'delta_outside_target_range' => l10n.incomePlannerRejectDelta,
      'delta_unavailable' => l10n.incomePlannerRejectDeltaUnavailable,
      'leaps_budget_exceeded' => l10n.incomePlannerRejectLeapsBudget,
      'quote_unavailable' => l10n.incomePlannerRejectQuote,
      'strike_above_user_max_buy_price' ||
      'strike_below_user_min_sell_price' => l10n.incomePlannerRejectPriceIntent,
      'upcoming_earnings' ||
      'upcoming_macro_event' => l10n.incomePlannerRejectEventRisk,
      _ => l10n.incomePlannerRejectOther,
    };
