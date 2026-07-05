part of 'income_planner_page.dart';

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.opportunity});

  final OptionsOpportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final metrics = opportunity.metrics;
    final contract = opportunity.contract;
    return SoftCard(
      onPress: () => showOpportunityDetailSheet(context, opportunity),
      borderRadius: AppRadius.md,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppBadge(
                  label: optionsStrategyKindShortLabel(
                    l10n,
                    opportunity.strategy,
                  ),
                  tone: AppBadgeTone.accent,
                ),
                const SizedBox(width: AppSpacing.s8),
                AppBadge(
                  label: _riskLabel(l10n, opportunity.risk),
                  tone: _riskTone(opportunity.risk),
                ),
                const Spacer(),
                Text(
                  '${contract.underlying} ${contract.dte}DTE',
                  style: context.labelStyle,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            _MetricsRow(metrics: metrics, contract: contract),
            const SizedBox(height: AppSpacing.s12),
            if (opportunity.explanation.whyGood.isNotEmpty) ...[
              Text(
                l10n.incomePlannerDetailWhyGood,
                style: context.captionLabelStyle.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              for (final line in opportunity.explanation.whyGood.take(2))
                _BulletRow(line: line),
            ],
            if (opportunity.explanation.whyRisky.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                l10n.incomePlannerDetailWhyRisky,
                style: context.captionLabelStyle.copyWith(
                  color: colors.destructive,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              for (final line in opportunity.explanation.whyRisky.take(2))
                _BulletRow(line: line),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.metrics, required this.contract});

  final OpportunityMetrics metrics;
  final OptionContract contract;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.s12,
      runSpacing: AppSpacing.s8,
      children: [
        _Metric(
          label: l10n.incomePlannerMetricStrike,
          value: MoneyText(
            amount: contract.strike.amount.toDouble(),
            currencyCode: contract.strike.currency,
            symbolStyle: MoneySymbolStyle.isoCode,
            style: context.labelStyle,
          ),
        ),
        _Metric(
          label: l10n.incomePlannerMetricOptionPrice,
          value: MoneyText(
            amount: contract.mid.amount.toDouble(),
            currencyCode: contract.mid.currency,
            symbolStyle: MoneySymbolStyle.isoCode,
            style: context.labelStyle,
          ),
        ),
        _Metric(
          label: l10n.incomePlannerMetricAnnualized,
          value: Text(_pct(metrics.annualizedYield), style: context.labelStyle),
        ),
        _Metric(
          label: l10n.incomePlannerMetricMargin,
          value: Text(_pct(metrics.marginOfSafety), style: context.labelStyle),
        ),
        _Metric(
          label: l10n.incomePlannerMetricCash,
          value: MoneyText(
            amount: metrics.cashRequired.amount.toDouble(),
            currencyCode: metrics.cashRequired.currency,
            symbolStyle: MoneySymbolStyle.isoCode,
            style: context.labelStyle,
          ),
        ),
      ],
    );
  }
}

class _ScanEmptyResultCard extends StatelessWidget {
  const _ScanEmptyResultCard({required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final universeEmpty = result.universe.isEmpty;
    final body = universeEmpty
        ? l10n.incomePlannerRefreshUniverseEmpty
        : l10n.incomePlannerOpportunitiesAllRejected;
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.incomePlannerNoMatchesTitle, style: context.labelStyle),
            const SizedBox(height: AppSpacing.s4),
            Text(body, style: context.bodyCaptionStyle.copyWith(height: 1.45)),
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.incomePlannerScanSummary(
                result.universe.length,
                result.rejected.length,
                result.errors.length,
              ),
              style: context.captionStyle,
            ),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(
                result.errors.entries
                    .take(2)
                    .map((e) => '${e.key}: ${e.value}')
                    .join('\n'),
                style: context.captionStyle.copyWith(
                  color: colors.destructive,
                  height: 1.35,
                ),
              ),
            ],
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(
                result.warnings.entries
                    .take(2)
                    .map((e) => '${e.key}: ${e.value}')
                    .join('\n'),
                style: context.captionStyle.copyWith(
                  color: SemanticColors.of(context).warning,
                  height: 1.35,
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

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s2),
        value,
      ],
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.s4, top: AppSpacing.s2),
      child: Text(
        '\u2022 $line',
        style: context.captionStyle.copyWith(height: 1.4),
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
  OpportunityRiskLevel.low => AppBadgeTone.accent,
  OpportunityRiskLevel.moderate => AppBadgeTone.neutral,
  OpportunityRiskLevel.elevated => AppBadgeTone.error,
};

String _pct(Decimal value) {
  final pct = (value * Decimal.fromInt(100)).toStringAsFixed(1);
  return '$pct%';
}
