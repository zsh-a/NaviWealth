part of 'tool_invocation_renderers.dart';

// ---------------------------------------------------------------------------
// compute_xirr -> big rate number + range label.
// Payload: { rate, from, to, scope, asset_id, currency, flows, ... }
// ---------------------------------------------------------------------------

class _XirrSummary extends StatelessWidget {
  const _XirrSummary({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final rate = _asDouble(outMap['rate']);
    final scope = _asString(outMap['scope']) ?? 'portfolio';
    final assetId = _asString(outMap['asset_id']);
    final from = _asDate(outMap['from']);
    final to = _asDate(outMap['to']);
    final flows = _asList(outMap['flows']) ?? const <Object?>[];

    final scopeLabel = scope == 'asset' && assetId != null
        ? l10n.aiToolXirrAssetScope(assetId)
        : l10n.aiToolXirrPortfolioScope;
    final rangeLabel = (from != null && to != null)
        ? '${_displayDate(from)} → ${_displayDate(to)}'
        : l10n.aiToolAllHistory;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(scopeLabel, style: context.microCaptionStyle),
          const SizedBox(height: AppSpacing.s4),
          if (rate == null)
            Text(l10n.aiToolXirrUnavailable, style: context.bodyCaptionStyle)
          else
            DeltaText(
              value: rate * 100,
              format: DeltaFormat.percent,
              fractionDigits: 2,
              style: TypographyTokens.numericTitle,
            ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            '$rangeLabel · ${l10n.aiToolCashFlowCount(flows.length)}',
            style: context.captionStyle,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// compute_net_worth / get_net_worth_summary -> mini sparkline + endpoints.
// Legacy payload: { from, to, granularity, series: [ { date, value, currency } ] }
// Device payload: { from, to, series: [ { year_month, cumulative_minor, currency } ] }
// ---------------------------------------------------------------------------

class _NetWorthSparkline extends StatelessWidget {
  const _NetWorthSparkline({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final raw = _asList(outMap['series']) ?? const <Object?>[];
    final points = <(DateTime, double)>[];
    String currency = 'CNY';
    for (final item in raw) {
      final m = _asMap(item);
      if (m == null) continue;
      final d = _netWorthPointDate(m);
      final v = _netWorthPointValue(m);
      if (d == null || v == null) continue;
      points.add((d, v));
      final c = _asString(m['currency']);
      if (c != null && c.isNotEmpty) currency = c;
    }
    if (points.isEmpty) {
      return _EmptyResult(message: l10n.aiToolNetWorthEmpty);
    }
    points.sort((a, b) => a.$1.compareTo(b.$1));
    final start = points.first.$2;
    final end = points.last.$2;
    final delta = end - start;

    final chartPoints = <ChartPoint>[
      for (final p in points)
        ChartPoint(x: p.$1.millisecondsSinceEpoch.toDouble(), y: p.$2),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.aiToolCurrentNetWorth,
                      style: context.microCaptionStyle,
                    ),
                    MoneyText(
                      amount: end,
                      currencyCode: currency,
                      style: TypographyTokens.numericTitle,
                      color: context.theme.colors.foreground,
                    ),
                  ],
                ),
              ),
              DeltaChip(value: delta, format: DeltaFormat.currency),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          SizedBox(
            height: AppControlHeights.chipRail,
            child: NwLineChart(
              series: [
                ChartSeries(
                  name: l10n.aiToolNetWorthSeriesName,
                  points: chartPoints,
                  intent: SeriesIntent.primary,
                  fillOpacity: 0.12,
                ),
              ],
              xAxis: const TimeAxis(showGrid: false, maxLabels: 0),
              yAxis: const ValueAxis(showGrid: false, maxLabels: 0),
              aspectRatio: 4,
              filled: true,
              downsample: false,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            '${_displayDate(points.first.$1)} → ${_displayDate(points.last.$1)} · ${l10n.aiToolSamplePointCount(points.length)}',
            style: context.microCaptionStyle,
          ),
        ],
      ),
    );
  }
}

DateTime? _netWorthPointDate(Map<String, Object?> row) {
  final date = _asDate(row['date']);
  if (date != null) return date;
  final yearMonth = _asString(row['year_month']);
  if (yearMonth == null) return null;
  final parts = yearMonth.split('-');
  if (parts.length != 2) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return null;
  return DateTime.utc(year, month);
}

double? _netWorthPointValue(Map<String, Object?> row) {
  final value = _asDouble(row['value']);
  if (value != null) return value;
  final minor = _asDouble(row['cumulative_minor']);
  if (minor == null) return null;
  return minor / 100.0;
}
