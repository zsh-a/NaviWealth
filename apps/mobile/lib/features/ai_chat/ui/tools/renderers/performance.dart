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

    return ToolResultSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(scopeLabel, style: context.microCaptionStyle),
          const SizedBox(height: AppSpacing.s6),
          if (rate == null)
            Text(l10n.aiToolXirrUnavailable, style: context.bodyCaptionStyle)
          else
            DeltaText(
              value: rate * 100,
              format: DeltaFormat.percent,
              fractionDigits: 2,
              style: TypographyTokens.numericTitle,
            ),
          const SizedBox(height: AppSpacing.s6),
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
// compute_net_worth / get_net_worth_summary -> answer-grade trend card.
// Legacy payload: { from, to, granularity, series: [ { date, value, currency } ] }
// Device payload: { from, to, series: [ { year_month, cumulative_minor, currency } ] }
//
// Device tool is monthly cumulative *net cash flow*, not mark-to-market
// net worth — labels and captions must say so honestly.
// ---------------------------------------------------------------------------

class _NetWorthSparkline extends StatefulWidget {
  const _NetWorthSparkline({required this.output});
  final Object? output;

  @override
  State<_NetWorthSparkline> createState() => _NetWorthSparklineState();
}

class _NetWorthSparklineState extends State<_NetWorthSparkline> {
  ChartPoint? _scrub;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(widget.output);
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
      return ToolResultSurface(
        child: _EmptyResult(message: l10n.aiToolNetWorthEmpty),
      );
    }
    points.sort((a, b) => a.$1.compareTo(b.$1));
    final start = points.first.$2;
    final end = points.last.$2;
    final delta = end - start;
    final pct = start.abs() < 1e-9 ? null : (delta / start.abs()) * 100;

    final chartPoints = <ChartPoint>[
      for (final p in points)
        ChartPoint(
          x: p.$1.millisecondsSinceEpoch.toDouble(),
          y: p.$2,
          meta: p.$1,
        ),
    ];

    final displayAmount = _scrub?.y ?? end;
    final displayDate = _scrub?.meta is DateTime
        ? _scrub!.meta! as DateTime
        : points.last.$1;

    return ToolResultSurface(
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
                    Text(
                      l10n.aiToolCurrentNetWorth,
                      style: context.microLabelStyle.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    AnimatedMoneyText(
                      amount: displayAmount,
                      currencyCode: currency,
                      style: TypographyTokens.numericTitle,
                      color: context.theme.colors.foreground,
                      showSign: displayAmount < 0,
                      duration: Motion.ambient,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      _scrub != null
                          ? _displayDate(displayDate)
                          : l10n.aiToolNetWorthMethodNote,
                      style: context.microCaptionStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DeltaChip(
                    value: delta,
                    format: DeltaFormat.currency,
                    currencyCode: currency,
                  ),
                  if (pct != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    DeltaChip(
                      value: pct,
                      format: DeltaFormat.percent,
                      fractionDigits: 1,
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          SizedBox(
            height: 112,
            child: NwLineChart(
              series: [
                ChartSeries(
                  name: l10n.aiToolNetWorthSeriesName,
                  points: chartPoints,
                  intent: SeriesIntent.primary,
                  fillOpacity: 0.16,
                ),
              ],
              xAxis: const TimeAxis(showGrid: false, maxLabels: 2),
              yAxis: const ValueAxis(showGrid: false, maxLabels: 0),
              aspectRatio: null,
              filled: true,
              downsample: false,
              heroDots: true,
              showDots: points.length <= 14,
              showXAxis: true,
              showYAxis: false,
              showTouchXAxisLabel: true,
              curved: false,
              onScrub: (point) {
                if (!mounted) return;
                setState(() => _scrub = point);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            '${_displayDate(points.first.$1)} → ${_displayDate(points.last.$1)}'
            ' · ${l10n.aiToolSamplePointCount(points.length)}'
            ' · ${l10n.aiToolNetWorthVsStart}',
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
