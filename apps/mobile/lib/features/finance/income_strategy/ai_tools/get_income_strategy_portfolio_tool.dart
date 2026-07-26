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
      'realized_result': snapshot.realizedResult.toString(),
      'projected_cash_90d': snapshot.projectedCash.toString(),
      'capital_at_risk': snapshot.capitalAtRisk.toString(),
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
              entityTable: flow.sourceTable,
              entityId: flow.sourceId,
              label:
                  '${underlying.asset.symbol} · ${flow.sleeve.wire} · ${flow.kind.name}',
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
    'realized_result': value.realizedResult.toString(),
    'actual_cash_movement': value.actualCashMovement.toString(),
    'projected_cash': value.projectedCash.toString(),
    'capital_at_risk': value.capitalAtRisk.toString(),
    'capital_budget': value.capitalBudget?.toString(),
    'annual_income_target': value.annualIncomeTarget?.toString(),
    'delta_equivalent_shares': value.deltaEquivalentShares?.toString(),
    'sleeves': [
      for (final sleeve in value.sleeves.values)
        <String, Object?>{
          'kind': sleeve.kind.wire,
          'status': sleeve.status,
          'realized_result': sleeve.realizedResult.toString(),
          'projected_cash': sleeve.projectedCash.toString(),
          'capital_at_risk': sleeve.capitalAtRisk.toString(),
          'market_value': sleeve.marketValue?.toString(),
          'delta_equivalent_shares': sleeve.deltaEquivalentShares?.toString(),
        },
    ],
    'risks': [
      for (final risk in value.risks)
        <String, Object?>{
          'code': risk.code.name,
          'severity': risk.severity.name,
          'sleeves': [for (final sleeve in risk.sleeves) sleeve.wire],
          'evidence': risk.evidence,
        },
    ],
  };
}
