part of 'dividend_center_page.dart';

class _DividendResilienceSection extends ConsumerWidget {
  const _DividendResilienceSection({
    required this.report,
    required this.currency,
    this.focusAssetId,
  });

  final DividendResilienceReport report;
  final String currency;
  final String? focusAssetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final confidence = switch (report.confidence) {
      DividendResilienceConfidence.high =>
        l10n.dividendResilienceConfidenceHigh,
      DividendResilienceConfidence.medium =>
        l10n.dividendResilienceConfidenceMedium,
      DividendResilienceConfidence.low => l10n.dividendResilienceConfidenceLow,
    };
    final start = report.periodStart;
    final coverage = start == null
        ? l10n.dividendResilienceNoCoverage
        : l10n.dividendResilienceCoverage(
            formatters.date(start),
            formatters.date(report.periodEnd),
            report.observedMonthCount,
            report.recordedMonthCount,
          );
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            title: l10n.dividendResilienceTitle,
            trailing: l10n.dividendResilienceConfidence(confidence),
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(coverage, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s2),
          Text(
            l10n.dividendResilienceCadenceCoverage(
              report.expectedPaymentCount,
              report.missingExpectedPaymentCount,
              report.irregularAssetCount,
            ),
            style: context.captionStyle,
          ),
          if (report.rolling.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s16),
            SizedBox(
              height: AppChartHeights.full,
              child: NwLineChart(
                series: [
                  ChartSeries(
                    name: l10n.dividendCenterGross,
                    points: [
                      for (final point in report.rolling)
                        ChartPoint(
                          x: point.asOf.millisecondsSinceEpoch.toDouble(),
                          y: point.gross.toDouble(),
                        ),
                    ],
                  ),
                  ChartSeries(
                    name: l10n.dividendResilienceNetSeries,
                    intent: SeriesIntent.benchmark,
                    points: [
                      for (final point in report.rolling)
                        ChartPoint(
                          x: point.asOf.millisecondsSinceEpoch.toDouble(),
                          y: point.net.toDouble(),
                        ),
                    ],
                  ),
                ],
                xAxis: const TimeAxis(
                  format: AxisDateFormat.monthYear,
                  maxLabels: 4,
                ),
                yAxis: ValueAxis.currency(currencyCode: currency, maxLabels: 4),
                interpolation: ChartInterpolation.linear,
                semanticLabel: l10n.dividendResilienceChartLabel,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s16),
          Wrap(
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s12,
            children: [
              _ResilienceMetric(
                label: l10n.dividendResilienceIncomeCagr,
                value: report.netIncomeCagr == null
                    ? l10n.commonNotAvailable
                    : formatters.signedPercent(report.netIncomeCagr!),
              ),
              _ResilienceMetric(
                label: l10n.dividendResilienceMaxDrawdown,
                value: report.maxDrawdown == null
                    ? l10n.commonNotAvailable
                    : formatters.percent(report.maxDrawdown!.ratio),
                detail: _recoveryText(l10n, report.maxDrawdown),
              ),
              _ResilienceMetric(
                label: l10n.dividendResilienceLargestSource,
                value: report.largestSourceLabel == null
                    ? l10n.commonNotAvailable
                    : report.largestSourceLabel!,
                detail: report.largestSourceShare == null
                    ? null
                    : formatters.percent(report.largestSourceShare!),
              ),
              _ResilienceMetric(
                label: l10n.dividendResilienceRetention,
                value: report.netRetentionRatio == null
                    ? l10n.commonNotAvailable
                    : formatters.percent(report.netRetentionRatio!),
              ),
            ],
          ),
          if (report.attributions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.dividendResilienceAttributionTitle,
              style: context.labelStyle,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.dividendResilienceAttributionHint,
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s10),
            for (final row in report.attributions.take(4))
              _AttributionRow(
                row: row,
                currency: currency,
                focused: row.assetId == focusAssetId,
              ),
          ],
          const SizedBox(height: AppSpacing.s14),
          AppStatusBanner(
            kind: report.confidence == DividendResilienceConfidence.low
                ? AppStatusKind.warning
                : AppStatusKind.info,
            message: l10n.dividendResilienceMethodology(
              (report.unitDividendMatchRatio * 100).round(),
              report.excludedEventCount,
            ),
          ),
        ],
      ),
    );
  }

  String? _recoveryText(
    AppLocalizations l10n,
    DividendIncomeDrawdown? drawdown,
  ) {
    if (drawdown == null) return null;
    final months = drawdown.recoveryMonths;
    return months == null
        ? l10n.dividendResilienceNotRecovered
        : l10n.dividendResilienceRecoveredIn(months);
  }
}

class _ResilienceMetric extends StatelessWidget {
  const _ResilienceMetric({
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: context.appTheme.metricTile.minWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s2),
          Text(value, style: TypographyTokens.numericBodyStrong),
          if (detail != null)
            Text(detail!, style: context.captionStyle, maxLines: 1),
        ],
      ),
    );
  }
}

class _AttributionRow extends ConsumerWidget {
  const _AttributionRow({
    required this.row,
    required this.currency,
    required this.focused,
  });

  final DividendChangeAttribution row;
  final String currency;
  final bool focused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final driver = switch (row.primaryDriver) {
      DividendChangeDriver.holdingQuantity =>
        l10n.dividendResilienceDriverHolding,
      DividendChangeDriver.unitDividend =>
        l10n.dividendResilienceDriverUnitDividend,
      DividendChangeDriver.fx => l10n.dividendResilienceDriverFx,
      DividendChangeDriver.localCombined =>
        l10n.dividendResilienceDriverCombined,
    };
    final amount = formatters.currency(row.totalChange.abs(), code: currency);
    final signed = row.totalChange >= Decimal.zero ? '+$amount' : '-$amount';
    String impact(Decimal value) {
      final formatted = formatters.currency(value.abs(), code: currency);
      return value >= Decimal.zero ? '+$formatted' : '-$formatted';
    }

    final detail = row.matchedUnitDividend
        ? l10n.dividendResilienceAttributionSplit(
            impact(row.holdingQuantityImpact),
            impact(row.unitDividendImpact),
            impact(row.fxImpact),
          )
        : l10n.dividendResilienceAttributionCombined(
            impact(row.localCombinedImpact),
            impact(row.fxImpact),
          );
    return AppTappable(
      key: ValueKey('dividend-attribution-${row.assetId}'),
      onPress: () => context.push(FinanceRoutes.wealthAsset(row.assetId)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
        decoration: focused
            ? BoxDecoration(
                color: context.theme.colors.primary.withValues(
                  alpha: AppOpacity.softTint,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.assetLabel, style: context.labelStyle),
                  Text(driver, style: context.captionStyle),
                  Text(detail, style: context.captionStyle),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(signed, style: TypographyTokens.numericBodyStrong),
            const SizedBox(width: AppSpacing.s4),
            const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
          ],
        ),
      ),
    );
  }
}
