import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../design_system/design_system.dart';

/// Maximum number of rows a list-style renderer will draw before
/// collapsing the rest behind a "+ N 项" hint. Keeps the assistant
/// reply readable when the model pulls back hundreds of ledger rows.
const int _kMaxVisibleRows = 10;

/// Above this raw row count we never fully expand inline — the user can
/// still drop into raw JSON if they need every entry. Mirrors the spec:
/// > 数据过大（> 50 条）→ 截断显示前 10 + 提示
const int _kRawListLimit = 50;

/// Build a specialised body widget for the `output` of [toolName]. Returns
/// `null` when no renderer is registered for the tool, when the payload
/// is the wrong shape, or when an exception is raised mid-render — the
/// caller should fall back to the pretty-printed JSON in that case.
///
/// The renderers are intentionally pure (no Riverpod, no controllers) so
/// the chat history can hot-reload them as plain Flutter widgets and the
/// widget tests can pump them directly.
Widget? renderToolOutput(
  BuildContext context,
  String toolName,
  Object? output,
) {
  if (output == null) return null;
  try {
    return switch (toolName) {
      'get_holdings' => _HoldingsTable(output: output),
      'compute_xirr' => _XirrSummary(output: output),
      'compute_net_worth' => _NetWorthSparkline(output: output),
      'get_industry_breakdown' ||
      'get_geo_breakdown' ||
      'get_market_cap_breakdown' => _BreakdownView(output: output),
      'get_risk_alerts' => _RiskAlertList(output: output),
      // Analytical / Snapshot read-model renderers.
      'get_asset_allocation' => AssetAllocationView(output: output),
      'get_recurring_patterns' => RecurringPatternsView(output: output),
      'get_subscription_changes' => SubscriptionChangesView(output: output),
      'get_refund_links' => RefundLinksView(output: output),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Shared parsing helpers — backend numbers may arrive as int, double or
// string depending on the JSON encoder, so coerce defensively.
// ---------------------------------------------------------------------------

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String? _asString(Object? v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

DateTime? _asDate(Object? v) {
  if (v is! String) return null;
  return DateTime.tryParse(v);
}

Map<String, Object?>? _asMap(Object? v) {
  if (v is Map) {
    return v.map((k, value) => MapEntry(k.toString(), value));
  }
  return null;
}

List<Object?>? _asList(Object? v) {
  if (v is List) return List<Object?>.from(v);
  return null;
}

String _displayDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d.toLocal());

// ---------------------------------------------------------------------------
// get_holdings → mini holdings table.
// Payload: { holdings: { <asset_id>: { symbol, name, net_quantity,
//           avg_unit_cost, cost_basis, currency } }, ... }
// ---------------------------------------------------------------------------

class _HoldingsTable extends StatelessWidget {
  const _HoldingsTable({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final holdings = _asMap(outMap['holdings']);
    if (holdings == null || holdings.isEmpty) {
      return const _EmptyResult(message: '暂无持仓数据');
    }

    final rows = <_HoldingRow>[];
    for (final entry in holdings.entries) {
      final m = _asMap(entry.value);
      if (m == null) continue;
      rows.add(
        _HoldingRow(
          assetId: entry.key,
          symbol: _asString(m['symbol']),
          name: _asString(m['name']),
          quantity: _asDouble(m['net_quantity']) ?? 0,
          costBasis: _asDouble(m['cost_basis']) ?? 0,
          avgCost: _asDouble(m['avg_unit_cost']),
          currency: _asString(m['currency']) ?? 'CNY',
        ),
      );
    }
    if (rows.isEmpty) return const _EmptyResult(message: '暂无持仓数据');
    rows.sort((a, b) => b.costBasis.compareTo(a.costBasis));
    final visible = rows.take(_kMaxVisibleRows).toList();
    final hidden = rows.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  '资产',
                  style: context.theme.typography.xs2.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  '数量',
                  textAlign: TextAlign.right,
                  style: context.theme.typography.xs2.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  '成本',
                  textAlign: TextAlign.right,
                  style: context.theme.typography.xs2.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final row in visible) _holdingRowTile(context, row),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4, left: AppSpacing.s8),
            child: Text(
              '还有 $hidden 项未展示',
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }

  Widget _holdingRowTile(BuildContext context, _HoldingRow row) {
    final qtyText = NumberFormat.decimalPattern().format(row.quantity);
    final primary = row.symbol ?? row.name ?? row.assetId;
    final secondary = row.symbol != null && row.name != null ? row.name! : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.theme.colors.border.withValues(alpha: AppOpacity.muted),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (secondary != null)
                  Text(
                    secondary,
                    style: context.theme.typography.xs2.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              qtyText,
              textAlign: TextAlign.right,
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.foreground,
                fontFeatures: TypographyTokens.tabularFigures,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: MoneyText(
                amount: row.costBasis,
                currencyCode: row.currency,
                style: context.theme.typography.xs,
                color: context.theme.colors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldingRow {
  const _HoldingRow({
    required this.assetId,
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.costBasis,
    required this.avgCost,
    required this.currency,
  });
  final String assetId;
  final String? symbol;
  final String? name;
  final double quantity;
  final double costBasis;
  final double? avgCost;
  final String currency;
}

// ---------------------------------------------------------------------------
// compute_xirr → big rate number + range label.
// Payload: { rate, from, to, scope, asset_id, currency, flows, ... }
// ---------------------------------------------------------------------------

class _XirrSummary extends StatelessWidget {
  const _XirrSummary({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final rate = _asDouble(outMap['rate']);
    final scope = _asString(outMap['scope']) ?? 'portfolio';
    final assetId = _asString(outMap['asset_id']);
    final from = _asDate(outMap['from']);
    final to = _asDate(outMap['to']);
    final flows = _asList(outMap['flows']) ?? const <Object?>[];

    final scopeLabel = scope == 'asset' && assetId != null
        ? '资产 $assetId'
        : '组合整体';
    final rangeLabel = (from != null && to != null)
        ? '${_displayDate(from)} → ${_displayDate(to)}'
        : '全部历史';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scopeLabel,
            style: context.theme.typography.xs2.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          if (rate == null)
            Text(
              '无法计算（现金流方向单一或样本不足）',
              style: context.theme.typography.sm.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            )
          else
            DeltaText(
              value: rate * 100,
              format: DeltaFormat.percent,
              fractionDigits: 2,
              style: TypographyTokens.numericTitle,
            ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            '$rangeLabel · ${flows.length} 条现金流',
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// compute_net_worth → mini sparkline + endpoints.
// Payload: { from, to, granularity, series: [ { date, value, currency } ] }
// ---------------------------------------------------------------------------

class _NetWorthSparkline extends StatelessWidget {
  const _NetWorthSparkline({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final raw = _asList(outMap['series']) ?? const <Object?>[];
    final points = <(DateTime, double)>[];
    String currency = 'CNY';
    for (final item in raw) {
      final m = _asMap(item);
      if (m == null) continue;
      final d = _asDate(m['date']);
      final v = _asDouble(m['value']);
      if (d == null || v == null) continue;
      points.add((d, v));
      final c = _asString(m['currency']);
      if (c != null && c.isNotEmpty) currency = c;
    }
    if (points.isEmpty) {
      return const _EmptyResult(message: '区间内没有净资产数据');
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
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
                      '当前净资产',
                      style: context.theme.typography.xs2.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
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
            height: 40,
            child: NwLineChart(
              series: [
                ChartSeries(
                  name: '净资产',
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
            '${_displayDate(points.first.$1)} → ${_displayDate(points.last.$1)} · ${points.length} 个采样点',
            style: context.theme.typography.xs2.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// get_*_breakdown → compact pie + top 3 categories.
// Payload: { total, buckets: [ { label, cost_basis, share, currency } ] }
// ---------------------------------------------------------------------------

class _BreakdownView extends StatelessWidget {
  const _BreakdownView({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final raw = _asList(outMap['buckets']) ?? const <Object?>[];
    final buckets = <_BreakdownBucket>[];
    for (final item in raw) {
      final m = _asMap(item);
      if (m == null) continue;
      final label = _asString(m['label']) ?? 'unknown';
      final cost = _asDouble(m['cost_basis']) ?? 0;
      final share = _asDouble(m['share']) ?? 0;
      final currency = _asString(m['currency']) ?? 'CNY';
      buckets.add(
        _BreakdownBucket(
          label: label,
          cost: cost,
          share: share,
          currency: currency,
        ),
      );
    }
    if (buckets.isEmpty) {
      return const _EmptyResult(message: '没有可分布的成本');
    }
    buckets.sort((a, b) => b.cost.compareTo(a.cost));
    final palette = ChartPalette.of(context);
    final top = buckets.take(3).toList();

    final slices = <Slice>[
      for (var i = 0; i < buckets.length; i++)
        Slice(
          label: buckets[i].label,
          value: buckets[i].share.clamp(0.0, 1.0) * 100,
          colorOverride: palette.accentAt(i),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: NwPieChart(
              slices: slices,
              hole: 0.62,
              minLabelPercent: 100, // hide in-slice labels for mini view
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < top.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: palette.accentAt(i),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s6),
                        Expanded(
                          child: Text(
                            top[i].label,
                            style: context.theme.typography.xs.copyWith(
                              color: context.theme.colors.foreground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          NumberFormat.percentPattern().format(
                            top[i].share.clamp(0.0, 1.0),
                          ),
                          style: context.theme.typography.xs.copyWith(
                            color: context.theme.colors.foreground,
                            fontFeatures: TypographyTokens.tabularFigures,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (buckets.length > top.length)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s4),
                    child: Text(
                      '其他 ${buckets.length - top.length} 类共 '
                      '${NumberFormat.percentPattern().format(buckets.skip(top.length).fold<double>(0, (s, b) => s + b.share).clamp(0.0, 1.0))}',
                      style: context.theme.typography.xs2.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownBucket {
  const _BreakdownBucket({
    required this.label,
    required this.cost,
    required this.share,
    required this.currency,
  });
  final String label;
  final double cost;
  final double share;
  final String currency;
}

// ---------------------------------------------------------------------------
// get_risk_alerts → severity-tinted list.
// Payload: { alerts: [ { kind, asset_id?, symbol?, industry?, share,
//           threshold, severity, message } ] }
// ---------------------------------------------------------------------------

class _RiskAlertList extends StatelessWidget {
  const _RiskAlertList({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final raw = _asList(outMap['alerts']) ?? const <Object?>[];
    if (raw.isEmpty) {
      return const _EmptyResult(message: '没有触发的风险预警', positive: true);
    }
    final alerts = <_RiskAlert>[];
    for (final item in raw) {
      final m = _asMap(item);
      if (m == null) continue;
      alerts.add(
        _RiskAlert(
          severity: _asString(m['severity']) ?? 'medium',
          message: _asString(m['message']) ?? '',
          share: _asDouble(m['share']),
          subject:
              _asString(m['symbol']) ??
              _asString(m['industry']) ??
              _asString(m['asset_id']) ??
              '',
        ),
      );
    }
    if (alerts.isEmpty) return const SizedBox.shrink();
    final visible = alerts.take(_kMaxVisibleRows).toList();
    final hidden = alerts.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in visible) _alertTile(context, a),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4, left: AppSpacing.s8),
            child: Text(
              '还有 $hidden 项未展示',
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }

  Widget _alertTile(BuildContext context, _RiskAlert alert) {
    final semantic = SemanticColors.of(context);
    final (bg, fg, icon) = switch (alert.severity) {
      'high' => (
        semantic.dangerContainer,
        semantic.onDangerContainer,
        FLucideIcons.circleAlert,
      ),
      'low' => (
        semantic.infoContainer,
        semantic.onInfoContainer,
        FLucideIcons.info,
      ),
      _ => (
        semantic.warningContainer,
        semantic.onWarningContainer,
        FLucideIcons.triangleAlert,
      ),
    };
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.s4),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppIconSizes.sm, color: fg),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.subject.isEmpty ? '风险预警' : alert.subject,
                  style: context.theme.typography.xs2.copyWith(color: fg),
                ),
                Text(
                  alert.message,
                  style: context.theme.typography.xs.copyWith(color: fg),
                ),
              ],
            ),
          ),
          if (alert.share != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.s8),
              child: Text(
                NumberFormat.percentPattern().format(
                  alert.share!.clamp(0.0, 1.0),
                ),
                style: context.theme.typography.xs2.copyWith(
                  color: fg,
                  fontFeatures: TypographyTokens.tabularFigures,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RiskAlert {
  const _RiskAlert({
    required this.severity,
    required this.message,
    required this.share,
    required this.subject,
  });
  final String severity;
  final String message;
  final double? share;
  final String subject;
}

// ---------------------------------------------------------------------------
// Shared empty placeholder.
// ---------------------------------------------------------------------------

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.message, this.positive = false});
  final String message;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s8),
      child: Row(
        children: [
          Icon(
            positive ? FLucideIcons.circleCheck : FLucideIcons.inbox,
            size: AppIconSizes.sm,
            color: context.theme.colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            message,
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether the renderer for [toolName] would normally render the entire
/// payload inline. Callers can use this to decide whether to keep raw JSON
/// hidden behind a "查看 raw JSON" toggle even when the payload itself is
/// huge.
// ===========================================================================
// Domain renderers for Snapshot/Analytical read-model tools.
// Calm Intelligence: surface tone, no glow, type-first layout. Each view
// degrades gracefully (empty / off-shape payloads) and never throws.
// ===========================================================================

// ---------------------------------------------------------------------------
// get_asset_allocation → donut + weight list.
// Payload shape: { buckets: [{bucket_dim, bucket_key, currency,
//   total_cost_minor (string), position_count (int), weight (double)}],
//   count, freshness, note }
// Weights are normalised per-currency (sum=1 within a currency); when the
// caller mixes multiple currencies we split into per-currency groups so
// the donut stays interpretable.
// ---------------------------------------------------------------------------

class AssetAllocationView extends StatelessWidget {
  const AssetAllocationView({super.key, required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final m = _asMap(output);
    final raw = _asList(m?['buckets']) ?? const <Object?>[];
    if (raw.isEmpty) {
      return const _EmptyHint(text: '尚无持仓数据');
    }
    final colors = context.theme.colors;
    final palette = <Color>[
      colors.primary,
      colors.secondary,
      colors.mutedForeground,
      colors.primary.withValues(alpha: 0.3),
      colors.secondary.withValues(alpha: 0.15),
      colors.border,
    ];

    // Group by currency so the donut totals are meaningful.
    final byCurrency = <String, List<_AllocBucket>>{};
    for (final b in raw) {
      final mb = _asMap(b);
      if (mb == null) continue;
      final bucket = _AllocBucket.fromJson(mb);
      if (bucket == null) continue;
      byCurrency
          .putIfAbsent(bucket.currency, () => <_AllocBucket>[])
          .add(bucket);
    }
    if (byCurrency.isEmpty) {
      return const _EmptyHint(text: '持仓数据格式异常');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in byCurrency.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s12),
            child: _AllocBlock(
              currency: entry.key,
              buckets: entry.value,
              palette: palette,
            ),
          ),
      ],
    );
  }
}

class _AllocBucket {
  const _AllocBucket({
    required this.key,
    required this.currency,
    required this.totalMinor,
    required this.positions,
    required this.weight,
  });
  final String key;
  final String currency;
  final int totalMinor;
  final int positions;
  final double weight;

  static _AllocBucket? fromJson(Map<String, Object?> m) {
    final key = _asString(m['bucket_key']);
    final currency = _asString(m['currency']);
    if (key == null || currency == null) return null;
    return _AllocBucket(
      key: key,
      currency: currency,
      totalMinor: int.tryParse(_asString(m['total_cost_minor']) ?? '0') ?? 0,
      positions: (m['position_count'] is int)
          ? m['position_count']! as int
          : (int.tryParse(_asString(m['position_count']) ?? '0') ?? 0),
      weight: _asDouble(m['weight']) ?? 0.0,
    );
  }
}

class _AllocBlock extends StatelessWidget {
  const _AllocBlock({
    required this.currency,
    required this.buckets,
    required this.palette,
  });
  final String currency;
  final List<_AllocBucket> buckets;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final sorted = [...buckets]..sort((a, b) => b.weight.compareTo(a.weight));
    final fmt = NumberFormat.decimalPattern();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: context.theme.colors.secondary.withValues(alpha: AppOpacity.disabled),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currency,
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.s10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CustomPaint(
                  painter: _DonutPainter(
                    slices: sorted,
                    palette: palette,
                    background: context.theme.colors.background,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < sorted.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: palette[i % palette.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s6),
                            Expanded(
                              child: Text(
                                sorted[i].key,
                                style: context.theme.typography.xs,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${(sorted[i].weight * 100).toStringAsFixed(1)}%',
                              style: context.theme.typography.xs.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            '合计成本 ${fmt.format(sorted.fold<int>(0, (a, b) => a + b.totalMinor) / 100.0)} · ${sorted.length} 类持仓',
            style: context.theme.typography.xs2.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.palette,
    required this.background,
  });
  final List<_AllocBucket> slices;
  final List<Color> palette;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (a, b) => a + b.weight);
    if (total <= 0) return;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - 1,
    );
    var start = -math.pi / 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.butt;
    for (var i = 0; i < slices.length; i++) {
      final sweep = (slices[i].weight / total) * math.pi * 2;
      stroke.color = palette[i % palette.length];
      canvas.drawArc(rect.deflate(6), start, sweep, false, stroke);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.palette != palette;
}

// ---------------------------------------------------------------------------
// get_recurring_patterns → subscription cards with cadence chips.
// Payload shape: { patterns: [{id, merchant_key, cadence, currency,
//   median_amount_minor (string), occurrences (int), last_seen_at}],
//   count, freshness, source, note }
// ---------------------------------------------------------------------------

class RecurringPatternsView extends StatelessWidget {
  const RecurringPatternsView({super.key, required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final m = _asMap(output);
    final raw = _asList(m?['patterns']) ?? const <Object?>[];
    if (raw.isEmpty) {
      return const _EmptyHint(text: '尚未检测到稳定的周期性支出');
    }
    final visible = raw.take(_kMaxVisibleRows).toList();
    final fmt = NumberFormat.decimalPattern();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: _patternRow(context, entry, fmt),
          ),
        if (raw.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: Text(
              '+ 还有 ${raw.length - visible.length} 项',
              style: context.theme.typography.xs2.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }

  Widget _patternRow(
    BuildContext context,
    Object? entry,
    NumberFormat fmt,
  ) {
    final mp = _asMap(entry);
    if (mp == null) return const SizedBox.shrink();
    final merchant = _asString(mp['merchant_key']) ?? '(unknown)';
    final cadence = _asString(mp['cadence']) ?? '?';
    final currency = _asString(mp['currency']) ?? '';
    final medianMinor =
        int.tryParse(_asString(mp['median_amount_minor']) ?? '0') ?? 0;
    final occ = (mp['occurrences'] is int)
        ? mp['occurrences']! as int
        : int.tryParse(_asString(mp['occurrences']) ?? '0') ?? 0;
    final lastSeen = _asDate(mp['last_seen_at']);
    final cadenceLabel = switch (cadence) {
      'monthly' => '每月',
      'weekly' => '每周',
      _ => cadence,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s10),
      decoration: BoxDecoration(
        color: context.theme.colors.secondary.withValues(alpha: AppOpacity.disabled),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchant,
                  style: context.theme.typography.sm.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: AppSpacing.s2),
                Row(
                  children: [
                    _miniChip(context, cadenceLabel),
                    const SizedBox(width: AppSpacing.s6),
                    Text(
                      '$occ 次${lastSeen != null ? ' · 最近 ${_displayDate(lastSeen)}' : ''}',
                      style: context.theme.typography.xs2.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Text(
            '${fmt.format(medianMinor.abs() / 100.0)} $currency',
            style: context.theme.typography.sm.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _miniChip(BuildContext context, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6, vertical: 1),
    decoration: BoxDecoration(
      color: context.theme.colors.border.withValues(alpha: AppOpacity.light),
      borderRadius: BorderRadius.circular(AppRadius.full),
    ),
    child: Text(
      label,
      style: context.theme.typography.xs2.copyWith(
        color: context.theme.colors.mutedForeground,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// get_subscription_changes → price-diff bars (↑/↓).
// Payload shape: { changes: [{id, merchant_key, cadence, currency,
//   prev_amount_minor (string), new_amount_minor (string),
//   delta_ratio (double), since (iso datetime)}], count, freshness }
// ---------------------------------------------------------------------------

class SubscriptionChangesView extends StatelessWidget {
  const SubscriptionChangesView({super.key, required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final m = _asMap(output);
    final raw = _asList(m?['changes']) ?? const <Object?>[];
    if (raw.isEmpty) {
      return const _EmptyHint(text: '本期未检测到订阅价格变化');
    }
    final visible = raw.take(_kMaxVisibleRows).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: _changeRow(context, entry),
          ),
        if (raw.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: Text(
              '+ 还有 ${raw.length - visible.length} 项',
              style: context.theme.typography.xs2.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }

  Widget _changeRow(BuildContext context, Object? entry) {
    final mp = _asMap(entry);
    if (mp == null) return const SizedBox.shrink();
    final merchant = _asString(mp['merchant_key']) ?? '(unknown)';
    final currency = _asString(mp['currency']) ?? '';
    final prev = int.tryParse(_asString(mp['prev_amount_minor']) ?? '') ?? 0;
    final next = int.tryParse(_asString(mp['new_amount_minor']) ?? '') ?? 0;
    final delta = _asDouble(mp['delta_ratio']) ?? 0.0;
    final since = _asDate(mp['since']);
    final up = next.abs() > prev.abs();
    final accent = up ? context.theme.colors.destructive : context.theme.colors.primary;
    final fmt = NumberFormat.decimalPattern();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: AppOpacity.faint),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: accent.withValues(alpha: AppOpacity.muted)),
      ),
      child: Row(
        children: [
          Icon(
            up ? FLucideIcons.trendingUp : FLucideIcons.trendingDown,
            size: AppIconSizes.h18,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchant,
                  style: context.theme.typography.sm.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  '${fmt.format(prev.abs() / 100.0)} → ${fmt.format(next.abs() / 100.0)} $currency'
                  '${since != null ? ' · 自 ${_displayDate(since)}' : ''}',
                  style: context.theme.typography.xs2.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            '${delta >= 0 ? '+' : ''}${(delta * 100).toStringAsFixed(1)}%',
            style: context.theme.typography.sm.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// get_refund_links → original ↔ refund pair cards.
// Payload shape: { links: [{id, original_txn_id, refund_txn_id,
//   amount_minor (string), currency, payload}], count, freshness }
// ---------------------------------------------------------------------------

class RefundLinksView extends StatelessWidget {
  const RefundLinksView({super.key, required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final m = _asMap(output);
    final raw = _asList(m?['links']) ?? const <Object?>[];
    if (raw.isEmpty) {
      return const _EmptyHint(text: '尚未检测到退款配对');
    }
    final visible = raw.take(_kMaxVisibleRows).toList();
    final fmt = NumberFormat.decimalPattern();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: _pairRow(context, entry, fmt),
          ),
        if (raw.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: Text(
              '+ 还有 ${raw.length - visible.length} 项',
              style: context.theme.typography.xs2.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }

  Widget _pairRow(BuildContext context, Object? entry, NumberFormat fmt) {
    final mp = _asMap(entry);
    if (mp == null) return const SizedBox.shrink();
    final origin = _asString(mp['original_txn_id']) ?? '?';
    final refund = _asString(mp['refund_txn_id']) ?? '?';
    final amountMinor = int.tryParse(_asString(mp['amount_minor']) ?? '') ?? 0;
    final currency = _asString(mp['currency']) ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s10),
      decoration: BoxDecoration(
        color: context.theme.colors.secondary.withValues(alpha: AppOpacity.disabled),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      FLucideIcons.arrowDownLeft,
                      size: AppIconSizes.xs,
                      color: context.theme.colors.mutedForeground,
                    ),
                    const SizedBox(width: AppSpacing.s4),
                    Expanded(
                      child: Text(
                        origin,
                        style: context.theme.typography.sm.copyWith(
                          fontFamily: 'monospace',
                          color: context.theme.colors.mutedForeground,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Row(
                  children: [
                    Icon(FLucideIcons.arrowUpRight, size: AppIconSizes.xs, color: context.theme.colors.primary),
                    const SizedBox(width: AppSpacing.s4),
                    Expanded(
                      child: Text(
                        refund,
                        style: context.theme.typography.sm.copyWith(
                          fontFamily: 'monospace',
                          color: context.theme.colors.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Text(
            '${fmt.format(amountMinor.abs() / 100.0)} $currency',
            style: context.theme.typography.sm.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Text(
        text,
        style: context.theme.typography.xs.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      ),
    );
  }
}

bool isOversizedToolPayload(String toolName, Object? output) {
  final m = _asMap(output);
  if (m == null) return false;
  switch (toolName) {
    case 'get_holdings':
      final holdings = _asMap(m['holdings']);
      return (holdings?.length ?? 0) > _kRawListLimit;
    case 'compute_net_worth':
      final list = _asList(m['series']);
      return (list?.length ?? 0) > _kRawListLimit;
    case 'get_risk_alerts':
      final list = _asList(m['alerts']);
      return (list?.length ?? 0) > _kRawListLimit;
    default:
      return false;
  }
}
