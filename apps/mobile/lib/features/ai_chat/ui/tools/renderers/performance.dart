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
// Multi-currency series are split; the user switches currency chips.
// ---------------------------------------------------------------------------

class _NetWorthSparkline extends StatefulWidget {
  const _NetWorthSparkline({required this.output});
  final Object? output;

  @override
  State<_NetWorthSparkline> createState() => _NetWorthSparklineState();
}

class _NetWorthSparklineState extends State<_NetWorthSparkline> {
  ChartPoint? _scrub;
  String? _currency;

  Map<String, List<(DateTime, double)>> _groupByCurrency(List<Object?> raw) {
    final byCur = <String, List<(DateTime, double)>>{};
    for (final item in raw) {
      final m = _asMap(item);
      if (m == null) continue;
      final d = _netWorthPointDate(m);
      final v = _netWorthPointValue(m);
      if (d == null || v == null) continue;
      final c = _asString(m['currency']);
      final currency = (c != null && c.isNotEmpty) ? c : 'CNY';
      byCur.putIfAbsent(currency, () => <(DateTime, double)>[]).add((d, v));
    }
    for (final list in byCur.values) {
      list.sort((a, b) => a.$1.compareTo(b.$1));
    }
    return byCur;
  }

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(widget.output);
    if (outMap == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final raw = _asList(outMap['series']) ?? const <Object?>[];
    final byCur = _groupByCurrency(raw);
    if (byCur.isEmpty) {
      return ToolResultSurface(
        child: _EmptyResult(message: l10n.aiToolNetWorthEmpty),
      );
    }

    final currencies = byCur.keys.toList()..sort();
    final currency = _currency != null && byCur.containsKey(_currency)
        ? _currency!
        : currencies.first;
    final points = byCur[currency]!;
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
          if (currencies.length > 1) ...[
            Wrap(
              spacing: AppSpacing.s6,
              runSpacing: AppSpacing.s4,
              children: [
                for (final c in currencies)
                  _CurrencyChip(
                    label: c,
                    selected: c == currency,
                    onTap: () => setState(() {
                      _currency = c;
                      _scrub = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s10),
          ],
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
            height: AppChartHeights.compact,
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
              onScrubChanged: (state) {
                if (!mounted) return;
                setState(() => _scrub = state?.point);
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
          const SizedBox(height: AppSpacing.s8),
          Align(
            alignment: Alignment.centerLeft,
            child: AppTappable(
              onPress: () {
                // Wealth hub is the full net-worth surface; path is stable
                // App route contract (avoid cross-feature import).
                pushFromAiSurface(context, '/wealth');
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.aiToolOpenWealth,
                    style: context.captionLabelStyle.copyWith(
                      color: context.theme.colors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Icon(
                    FLucideIcons.arrowUpRight,
                    size: AppIconSizes.xs,
                    color: context.theme.colors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return AppTappable(
      onPress: onTap,
      child: AnimatedContainer(
        duration: AppMotionPolicy.duration(context, Motion.fast),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: AppOpacity.subtle)
              : colors.muted.withValues(alpha: AppOpacity.prominent),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.scrim)
                : colors.border.withValues(alpha: AppOpacity.scrim),
            width: AppStroke.hairline,
          ),
        ),
        child: Text(
          label,
          style: context.microLabelStyle.copyWith(
            color: selected ? colors.primary : colors.mutedForeground,
          ),
        ),
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

/// Y-values for a collapsed mini-spark of net-worth-style tool output.
/// Returns null when the payload is not a usable series.
List<double>? netWorthSparkValues(Object? output) {
  final outMap = _asMap(output);
  if (outMap == null) return null;
  final raw = _asList(outMap['series']) ?? const <Object?>[];
  final byCur = <String, List<(DateTime, double)>>{};
  for (final item in raw) {
    final m = _asMap(item);
    if (m == null) continue;
    final d = _netWorthPointDate(m);
    final v = _netWorthPointValue(m);
    if (d == null || v == null) continue;
    final c = _asString(m['currency']);
    final currency = (c != null && c.isNotEmpty) ? c : 'CNY';
    byCur.putIfAbsent(currency, () => <(DateTime, double)>[]).add((d, v));
  }
  if (byCur.isEmpty) return null;
  // Prefer CNY, else first currency by name.
  final preferred = byCur.containsKey('CNY')
      ? 'CNY'
      : (byCur.keys.toList()..sort()).first;
  final pts = byCur[preferred]!..sort((a, b) => a.$1.compareTo(b.$1));
  if (pts.length < 2) return null;
  return [for (final p in pts) p.$2];
}

/// Tiny sparkline for collapsed multi-tool rows (no interaction).
class ToolMiniSpark extends StatelessWidget {
  const ToolMiniSpark({super.key, required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    final color = context.theme.colors.primary;
    return SizedBox(
      width: AppSpacing.s40,
      height: AppSpacing.s16,
      child: CustomPaint(
        painter: _MiniSparkPainter(values: values, color: color),
      ),
    );
  }
}

class _MiniSparkPainter extends CustomPainter {
  _MiniSparkPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var minV = values.first;
    var maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * (i / (values.length - 1));
      final y = size.height * (1 - (values[i] - minV) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppStroke.thin
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniSparkPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
