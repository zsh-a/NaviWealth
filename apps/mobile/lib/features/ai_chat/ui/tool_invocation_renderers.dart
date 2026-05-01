import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../design_system/design_system.dart';

/// Maximum number of rows a list-style renderer will draw before
/// collapsing the rest behind a "+ N 项" hint. Keeps the assistant
/// reply readable when the model pulls back hundreds of transactions.
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
      'get_transactions' => _TransactionList(output: output),
      'compute_xirr' => _XirrSummary(output: output),
      'compute_net_worth' => _NetWorthSparkline(output: output),
      'get_industry_breakdown' ||
      'get_geo_breakdown' ||
      'get_market_cap_breakdown' =>
        _BreakdownView(output: output),
      'get_risk_alerts' => _RiskAlertList(output: output),
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

String _displayDate(DateTime d) =>
    DateFormat('yyyy-MM-dd').format(d.toLocal());

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

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.s8,
            vertical: Spacing.s4,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  '资产',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  '数量',
                  textAlign: TextAlign.right,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  '成本',
                  textAlign: TextAlign.right,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        for (final row in visible) _holdingRowTile(context, row),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.s4, left: Spacing.s8),
            child: Text(
              '还有 $hidden 项未展示',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _holdingRowTile(BuildContext context, _HoldingRow row) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final qtyText = NumberFormat.decimalPattern().format(row.quantity);
    final primary = row.symbol ?? row.name ?? row.assetId;
    final secondary = row.symbol != null && row.name != null ? row.name! : null;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s6,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
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
                  style: tt.bodySmall?.copyWith(color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (secondary != null)
                  Text(
                    secondary,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
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
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface,
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
                style: tt.bodySmall,
                color: cs.onSurface,
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
// get_transactions → ListTile-style flow.
// Payload: { transactions: [ { id, type, assetId, accountId, quantity,
//           price, fee, currency, tradeDate, ... } ], truncated }
// ---------------------------------------------------------------------------

class _TransactionList extends StatelessWidget {
  const _TransactionList({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final list = _asList(outMap['transactions']);
    if (list == null || list.isEmpty) {
      return const _EmptyResult(message: '该筛选下没有交易');
    }
    final truncated = outMap['truncated'] == true;
    final visible = list.take(_kMaxVisibleRows).toList();
    final hidden = list.length - visible.length;

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final raw in visible)
          _transactionTile(context, _asMap(raw) ?? const <String, Object?>{}),
        if (hidden > 0 || truncated)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.s4, left: Spacing.s8),
            child: Text(
              [
                if (hidden > 0) '还有 $hidden 项未展示',
                if (truncated) '后端已截断结果',
              ].join(' · '),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _transactionTile(BuildContext context, Map<String, Object?> tx) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final type = _asString(tx['type']) ?? '';
    final qty = _asDouble(tx['quantity']) ?? 0;
    final price = _asDouble(tx['price']) ?? 0;
    final amount = qty * price;
    final currency = _asString(tx['currency']) ?? 'CNY';
    final assetId = _asString(tx['assetId']) ?? '';
    final date = _asDate(tx['tradeDate']);
    final sign = _txSign(type);
    final signed = amount * sign;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s6,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(_txIcon(type), size: 16, color: _txIconColor(context, type)),
          const SizedBox(width: Spacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _txLabel(type, assetId),
                  style: tt.bodySmall?.copyWith(color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (date != null)
                  Text(
                    _displayDate(date),
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (sign != 0)
            DeltaText(
              value: signed,
              currencyCode: currency,
              style: tt.bodySmall,
            )
          else
            MoneyText(
              amount: amount,
              currencyCode: currency,
              style: tt.bodySmall,
              color: cs.onSurface,
            ),
        ],
      ),
    );
  }

  IconData _txIcon(String type) => switch (type) {
        'buy' || 'reinvest' || 'transferIn' => Icons.arrow_downward,
        'sell' || 'transferOut' || 'withdraw' => Icons.arrow_upward,
        'dividend' || 'interest' => Icons.savings_outlined,
        'fee' || 'tax' => Icons.receipt_long_outlined,
        'liabilityPayment' => Icons.credit_card_outlined,
        'deposit' => Icons.account_balance_wallet_outlined,
        _ => Icons.swap_horiz,
      };

  Color _txIconColor(BuildContext context, String type) {
    final market = MarketColors.of(context);
    return switch (type) {
      'buy' || 'reinvest' || 'transferIn' || 'deposit' => market.up,
      'sell' || 'transferOut' || 'withdraw' || 'liabilityPayment' =>
        market.down,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  /// Sign for the delta line. 0 means render as a neutral money cell
  /// (we don't want to nudge the user with up/down colors for fees / tax).
  double _txSign(String type) => switch (type) {
        'buy' || 'reinvest' || 'transferIn' || 'deposit' => 1,
        'sell' || 'transferOut' || 'withdraw' || 'liabilityPayment' => -1,
        _ => 0,
      };

  String _txLabel(String type, String assetId) {
    final friendly = switch (type) {
      'buy' => '买入',
      'sell' => '卖出',
      'reinvest' => '再投资',
      'transferIn' => '转入',
      'transferOut' => '转出',
      'dividend' => '分红',
      'interest' => '利息',
      'deposit' => '存入',
      'withdraw' => '取出',
      'fee' => '手续费',
      'tax' => '税费',
      'liabilityPayment' => '负债还款',
      _ => type.isEmpty ? '交易' : type,
    };
    return assetId.isEmpty ? friendly : '$friendly · $assetId';
  }
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

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final scopeLabel = scope == 'asset' && assetId != null
        ? '资产 $assetId'
        : '组合整体';
    final rangeLabel = (from != null && to != null)
        ? '${_displayDate(from)} → ${_displayDate(to)}'
        : '全部历史';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scopeLabel,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.s4),
          if (rate == null)
            Text(
              '无法计算（现金流方向单一或样本不足）',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            DeltaText(
              value: rate * 100,
              format: DeltaFormat.percent,
              fractionDigits: 2,
              style: TypographyTokens.numericTitle,
            ),
          const SizedBox(height: Spacing.s4),
          Text(
            '$rangeLabel · ${flows.length} 条现金流',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
    final values = points.map((p) => p.$2).toList(growable: false);
    final start = values.first;
    final end = values.last;
    final delta = end - start;

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s4,
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
                      '当前净资产',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    MoneyText(
                      amount: end,
                      currencyCode: currency,
                      style: TypographyTokens.numericTitle,
                      color: cs.onSurface,
                    ),
                  ],
                ),
              ),
              DeltaChip(value: delta, format: DeltaFormat.currency),
            ],
          ),
          const SizedBox(height: Spacing.s8),
          SizedBox(
            height: 40,
            child: CustomPaint(
              painter: _SparklinePainter(
                values: values,
                color: Theme.of(context).colorScheme.primary,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: Spacing.s4),
          Text(
            '${_displayDate(points.first.$1)} → ${_displayDate(points.last.$1)} · ${points.length} 个采样点',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).abs();
    final span = range == 0 ? 1.0 : range;
    final stride = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = stride * i;
      final norm = range == 0 ? 0.5 : (values[i] - minV) / span;
      final y = size.height - norm * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = color.withValues(alpha: 0.12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CustomPaint(
              painter: _DonutPainter(
                slices: [for (final b in buckets) b.share.clamp(0.0, 1.0)],
                colors: [
                  for (var i = 0; i < buckets.length; i++) palette.accentAt(i),
                ],
                background: cs.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: Spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < top.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
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
                        const SizedBox(width: Spacing.s6),
                        Expanded(
                          child: Text(
                            top[i].label,
                            style: tt.bodySmall?.copyWith(color: cs.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          NumberFormat.percentPattern()
                              .format(top[i].share.clamp(0.0, 1.0)),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface,
                            fontFeatures: TypographyTokens.tabularFigures,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (buckets.length > top.length)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.s4),
                    child: Text(
                      '其他 ${buckets.length - top.length} 类共 '
                      '${NumberFormat.percentPattern().format(
                        buckets
                            .skip(top.length)
                            .fold<double>(0, (s, b) => s + b.share)
                            .clamp(0.0, 1.0),
                      )}',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
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

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.colors,
    required this.background,
  });
  final List<double> slices;
  final List<Color> colors;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    final center = size.center(Offset.zero);
    final stroke = radius * 0.32;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);
    final ringPaint = Paint()
      ..color = background
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius - stroke / 2, ringPaint);

    final total = slices.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final share = slices[i] / total;
      if (share <= 0) continue;
      final sweep = share * math.pi * 2;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.colors != colors;
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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in visible) _alertTile(context, a),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.s4, left: Spacing.s8),
            child: Text(
              '还有 $hidden 项未展示',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _alertTile(BuildContext context, _RiskAlert alert) {
    final semantic = SemanticColors.of(context);
    final tt = Theme.of(context).textTheme;
    final (bg, fg, icon) = switch (alert.severity) {
      'high' => (
        semantic.dangerContainer,
        semantic.onDangerContainer,
        Icons.error_outline,
      ),
      'low' => (
        semantic.infoContainer,
        semantic.onInfoContainer,
        Icons.info_outline,
      ),
      _ => (
        semantic.warningContainer,
        semantic.onWarningContainer,
        Icons.warning_amber_outlined,
      ),
    };
    return Container(
      margin: const EdgeInsets.only(top: Spacing.s4),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: Radii.brXs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: Spacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.subject.isEmpty ? '风险预警' : alert.subject,
                  style: tt.labelSmall?.copyWith(color: fg),
                ),
                Text(
                  alert.message,
                  style: tt.bodySmall?.copyWith(color: fg),
                ),
              ],
            ),
          ),
          if (alert.share != null)
            Padding(
              padding: const EdgeInsets.only(left: Spacing.s8),
              child: Text(
                NumberFormat.percentPattern()
                    .format(alert.share!.clamp(0.0, 1.0)),
                style: tt.labelSmall?.copyWith(
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s8,
      ),
      child: Row(
        children: [
          Icon(
            positive ? Icons.check_circle_outline : Icons.inbox_outlined,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.s8),
          Text(
            message,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
bool isOversizedToolPayload(String toolName, Object? output) {
  final m = _asMap(output);
  if (m == null) return false;
  switch (toolName) {
    case 'get_holdings':
      final holdings = _asMap(m['holdings']);
      return (holdings?.length ?? 0) > _kRawListLimit;
    case 'get_transactions':
      final list = _asList(m['transactions']);
      return (list?.length ?? 0) > _kRawListLimit;
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
