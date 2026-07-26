part of 'income_planner_page.dart';

enum _OpportunityFilter { all, put, call }

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
                        ? SemanticColors.of(context).warning
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
  });

  final ScanState state;
  final AsyncValue<List<OptionsOpportunity>> opportunitiesAsync;

  @override
  State<_OpportunitiesBody> createState() => _OpportunitiesBodyState();
}

class _OpportunitiesBodyState extends State<_OpportunitiesBody> {
  _OpportunityFilter _filter = _OpportunityFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.state is ScanFailure) {
      return _ErrorCard(
        title: l10n.incomePlannerRefreshFailedTitle,
        message: userSafeErrorMessage(
          context,
          (widget.state as ScanFailure).error,
        ),
      );
    }
    return widget.opportunitiesAsync.when(
      loading: () => const _LoadingTile(),
      error: (error, _) => _ErrorCard(
        title: l10n.incomePlannerRefreshFailedTitle,
        message: userSafeErrorMessage(context, error),
      ),
      data: (items) {
        if (items.isEmpty) {
          if (widget.state is ScanSuccess) {
            return _ScanEmptyResultCard(
              result: (widget.state as ScanSuccess).result,
            );
          }
          return _EmptyCard(body: l10n.incomePlannerOpportunitiesEmpty);
        }
        final visible = items.where(_matchesFilter).toList()
          ..sort((a, b) => b.score.compareTo(a.score));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedRow<_OpportunityFilter>(
              options: _OpportunityFilter.values,
              value: _filter,
              labelOf: (filter) => switch (filter) {
                _OpportunityFilter.all =>
                  l10n.incomePlannerOpportunityFilterAll,
                _OpportunityFilter.put => l10n.incomePlannerChipCashSecuredPut,
                _OpportunityFilter.call => l10n.incomePlannerChipCoveredCall,
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
              _EmptyCard(body: l10n.incomePlannerOpportunityFilterEmpty)
            else
              for (final opportunity in visible)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                  child: _OpportunityCard(opportunity: opportunity),
                ),
          ],
        );
      },
    );
  }

  bool _matchesFilter(OptionsOpportunity opportunity) => switch (_filter) {
    _OpportunityFilter.all => true,
    _OpportunityFilter.put =>
      opportunity.strategy == OptionsStrategyKind.cashSecuredPut,
    _OpportunityFilter.call =>
      opportunity.strategy == OptionsStrategyKind.coveredCall,
  };
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.opportunity});

  final OptionsOpportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final contract = opportunity.contract;
    final metrics = opportunity.metrics;
    final expiry = MaterialLocalizations.of(
      context,
    ).formatShortDate(contract.expiration.toLocal());
    return SoftCard.flat(
      onPress: () => showOpportunityDetailSheet(context, opportunity),
      borderRadius: AppRadius.lg,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
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
                      label: optionsStrategyKindShortLabel(
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
              items: [
                AppMetricItem(
                  label: l10n.incomePlannerMetricPremiumTotal,
                  value: _moneyCompact(metrics.premium),
                ),
                AppMetricItem(
                  label: l10n.incomePlannerMetricBreakeven,
                  value: _moneyCompact(metrics.breakeven),
                ),
                AppMetricItem(
                  label: l10n.incomePlannerMetricAnnualized,
                  value: _pct(metrics.annualizedYield),
                ),
              ],
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
      ),
    );
  }
}

class _ScanEmptyResultCard extends StatelessWidget {
  const _ScanEmptyResultCard({required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final universeEmpty = result.universe.isEmpty;
    final counts = <String, int>{};
    for (final rejected in result.rejected) {
      for (final reason in rejected.reasons) {
        counts.update(reason, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final topReasons = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SoftCard.flat(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
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
                  onPress: () => showApprovedUnderlyingSheet(context),
                  child: Text(l10n.incomePlannerAddApprovedCta),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

String _pct(Decimal value) {
  final pct = (value * Decimal.fromInt(100)).toStringAsFixed(1);
  return '$pct%';
}

String _moneyCompact(Money money) => '${money.currency} ${money.amount}';

String _rejectionReasonLabel(AppLocalizations l10n, String reason) =>
    switch (reason) {
      'cash_required_above_cap' => l10n.incomePlannerRejectCapitalLimit,
      'open_interest_below_minimum' ||
      'volume_below_minimum' => l10n.incomePlannerRejectLiquidity,
      'bid_ask_spread_above_maximum' => l10n.incomePlannerRejectSpread,
      'dte_outside_target_range' => l10n.incomePlannerRejectDte,
      'delta_outside_target_range' => l10n.incomePlannerRejectDelta,
      'strike_above_user_max_buy_price' ||
      'strike_below_user_min_sell_price' => l10n.incomePlannerRejectPriceIntent,
      'upcoming_earnings' ||
      'upcoming_macro_event' => l10n.incomePlannerRejectEventRisk,
      _ => l10n.incomePlannerRejectOther,
    };
