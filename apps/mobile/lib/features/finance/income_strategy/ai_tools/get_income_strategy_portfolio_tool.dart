import 'package:naviwealth/core/ai/contracts/evidence_anchor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../data/providers.dart';
import '../domain/income_strategy.dart';

/// Reads the same composable portfolio snapshot used by the strategy UI.
class GetIncomeStrategyPortfolioTool implements DeviceTool {
  const GetIncomeStrategyPortfolioTool();

  @override
  String get name => 'get_income_strategy_portfolio';

  @override
  String get description =>
      '读取按标的组合后的股息、Wheel 与 LEAPS 收益策略快照，包含实际现金流、'
      '已实现结果、预计股息、风险资本、策略模块和跨策略风险。'
      '这是只读派生视图，不触发行情扫描，也不会修改计划或仓位。'
      '回答整体收益策略、同一标的组合敞口或策略冲突前优先调用。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'asset_id': <String, Object?>{
        'type': 'string',
        'description': '可选的规范标的 id，例如 us_stock:AAPL。',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final snapshot = await ctx.ref.read(portfolioIncomeStrategyProvider.future);
    final filter = (input['asset_id'] as String?)?.trim();
    final underlyings = filter == null || filter.isEmpty
        ? snapshot.underlyings
        : snapshot.underlyings
              .where((value) => value.asset.assetId == filter)
              .toList(growable: false);
    final result = <String, Object?>{
      'base_currency': snapshot.baseCurrency,
      'as_of': snapshot.asOf.toIso8601String(),
      'period_start': snapshot.periodStart.toIso8601String(),
      'realized_income_ytd': snapshot.realizedIncome.value.amount.toString(),
      'realized_result_ytd': snapshot.realizedResult.value.amount.toString(),
      'projected_cash_90d': snapshot.projectedCash.value.amount.toString(),
      'capital_at_risk': snapshot.capitalAtRisk.value.amount.toString(),
      'active_risk_count': snapshot.activeRiskCount,
      'underlyings': [
        for (final underlying in underlyings) _underlyingToWire(underlying),
      ],
      if (filter != null && underlyings.isEmpty)
        'guidance': '$filter 没有收益策略计划、持仓、股息或期权记录。',
    };
    return withEvidence(
      result: result,
      anchors: [
        for (final underlying in underlyings)
          for (final flow in underlying.cashFlows)
            EvidenceAnchor(
              entityTable: flow.source.table,
              entityId: flow.source.id,
              label:
                  '${underlying.asset.symbol} · ${flow.sleeve.wire} · ${flow.kind.wire}',
            ),
      ],
    );
  }

  Map<String, Object?> _underlyingToWire(
    UnderlyingIncomeStrategySnapshot value,
  ) => <String, Object?>{
    'asset_id': value.asset.assetId,
    'symbol': value.asset.symbol,
    'market': value.asset.market,
    'currency': value.asset.currency,
    'enabled_sleeves': [for (final sleeve in value.enabledSleeves) sleeve.wire],
    'realized_income_ytd': value.realizedIncome.value.amount.toString(),
    'realized_result_ytd': value.realizedResult.value.amount.toString(),
    'actual_cash_movement_ytd': value.actualCashMovement.value.amount
        .toString(),
    'projected_cash': value.projectedCash.value.amount.toString(),
    'capital_at_risk': value.capitalAtRisk.value.amount.toString(),
    'capital_budget': value.capitalBudget?.amount.toString(),
    'annual_income_target': value.annualIncomeTarget?.amount.toString(),
    'delta_equivalent_shares': value.deltaEquivalentShares?.toString(),
    'sleeves': [
      for (final sleeve in value.sleeves.values)
        <String, Object?>{
          'kind': sleeve.kind.wire,
          'status': sleeve.status,
          'period_start': sleeve.periodStart.toIso8601String(),
          'as_of': sleeve.asOf.toIso8601String(),
          'realized_income_ytd': sleeve.realizedIncome.value.amount.toString(),
          'realized_result_ytd': sleeve.realizedResult.value.amount.toString(),
          'projected_cash': sleeve.projectedCash.value.amount.toString(),
          'capital_at_risk': sleeve.capitalAtRisk.value.amount.toString(),
          'capital_at_risk_quality': sleeve.capitalAtRisk.quality.name,
          'market_value': sleeve.marketValue?.value.amount.toString(),
          'market_value_quality': sleeve.marketValue?.quality.name,
          'delta_equivalent_shares': sleeve.deltaEquivalentShares?.toString(),
        },
    ],
    'risks': [
      for (final risk in value.risks)
        <String, Object?>{
          'code': risk.code.wire,
          'severity': risk.severity.name,
          'sleeves': [for (final sleeve in risk.sleeves) sleeve.wire],
          'evidence': risk.evidence,
        },
    ],
  };
}
