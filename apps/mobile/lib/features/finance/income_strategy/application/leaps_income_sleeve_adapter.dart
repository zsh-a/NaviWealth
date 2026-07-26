import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';

import 'income_strategy_asset_resolver.dart';

class LeapsIncomeSleeveAdapter {
  const LeapsIncomeSleeveAdapter();

  List<IncomeStrategySleeveContribution> build({
    required Iterable<LeapsCallPosition> positions,
    required IncomeStrategyAssetResolver assets,
    DateTime? now,
  }) {
    final grouped = <String, List<LeapsCallPosition>>{};
    for (final position in positions) {
      final asset = assets.fromSymbol(
        symbol: position.symbol,
        currency: position.currency,
        marketWire: position.underlyingMarket,
      );
      grouped
          .putIfAbsent(asset.assetId, () => <LeapsCallPosition>[])
          .add(position);
    }
    final clock = (now ?? DateTime.now()).toUtc();
    return [
      for (final entry in grouped.entries)
        _buildOne(
          asset: assets.fromSymbol(
            symbol: entry.value.first.symbol,
            currency: entry.value.first.currency,
            marketWire: entry.value.first.underlyingMarket,
          ),
          positions: entry.value,
          now: clock,
        ),
    ];
  }

  IncomeStrategySleeveContribution _buildOne({
    required IncomeStrategyAsset asset,
    required List<LeapsCallPosition> positions,
    required DateTime now,
  }) {
    final open = positions.where((position) => position.isOpen).toList();
    var openCost = Decimal.zero;
    var marketValue = Decimal.zero;
    var realized = Decimal.zero;
    var delta = Decimal.zero;
    var hasCompleteMark = open.isNotEmpty;
    var hasCompleteDelta = open.isNotEmpty;
    final risks = <IncomeStrategyRisk>[];
    final flows = <IncomeStrategyCashFlow>[];

    for (final position in positions) {
      flows.add(
        IncomeStrategyCashFlow(
          id: 'leaps:${position.id}:purchase',
          assetId: asset.assetId,
          sleeve: IncomeStrategySleeveKind.leapsCall,
          kind: IncomeStrategyCashFlowKind.leapsPurchase,
          state: IncomeStrategyCashFlowState.actual,
          date: position.openedAt,
          amount: -position.grossEntryCost,
          currency: position.currency,
          sourceTable: 'options_leaps_call_positions',
          sourceId: position.id,
          hasCompleteEvidence: true,
        ),
      );
      final proceeds = position.grossExitProceeds;
      if (proceeds != null) {
        flows.add(
          IncomeStrategyCashFlow(
            id: 'leaps:${position.id}:sale',
            assetId: asset.assetId,
            sleeve: IncomeStrategySleeveKind.leapsCall,
            kind: IncomeStrategyCashFlowKind.leapsSale,
            state: IncomeStrategyCashFlowState.actual,
            date: position.closedAt ?? position.expirationAt,
            amount: proceeds,
            currency: position.currency,
            sourceTable: 'options_leaps_call_positions',
            sourceId: position.id,
            hasCompleteEvidence: true,
          ),
        );
      }
      if (position.status == LeapsCallStatus.exercised) {
        flows.add(
          IncomeStrategyCashFlow(
            id: 'leaps:${position.id}:exercise',
            assetId: asset.assetId,
            sleeve: IncomeStrategySleeveKind.leapsCall,
            kind: IncomeStrategyCashFlowKind.leapsExercise,
            state: IncomeStrategyCashFlowState.actual,
            date: position.closedAt ?? position.expirationAt,
            amount:
                -position.strikePrice *
                Decimal.fromInt(
                  position.contractSize * position.contractQuantity,
                ),
            currency: position.currency,
            sourceTable: 'options_leaps_call_positions',
            sourceId: position.id,
            hasCompleteEvidence: true,
          ),
        );
      }
      if (!position.isOpen) {
        realized += position.realizedPnl ?? Decimal.zero;
        continue;
      }
      openCost += position.grossEntryCost;
      final markedValue = position.marketValue;
      if (markedValue == null) {
        hasCompleteMark = false;
      } else {
        marketValue += markedValue;
      }
      final deltaShares = position.deltaEquivalentShares;
      if (deltaShares == null) {
        hasCompleteDelta = false;
      } else {
        delta += deltaShares;
      }
      if (position.expirationAt.toUtc().difference(now).inDays <= 180) {
        risks.add(
          IncomeStrategyRisk(
            code: IncomeStrategyRiskCode.expirationNear,
            severity: IncomeStrategyRiskSeverity.warning,
            assetId: asset.assetId,
            sleeves: const {IncomeStrategySleeveKind.leapsCall},
            evidence: {
              'option_symbol': position.optionSymbol,
              'expiration_at': position.expirationAt.toIso8601String(),
            },
          ),
        );
      }
    }
    if (open.isNotEmpty && !hasCompleteMark) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.missingMarketValue,
          severity: IncomeStrategyRiskSeverity.info,
          assetId: asset.assetId,
          sleeves: const {IncomeStrategySleeveKind.leapsCall},
        ),
      );
    }
    if (open.isNotEmpty && !hasCompleteDelta) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.missingDelta,
          severity: IncomeStrategyRiskSeverity.info,
          assetId: asset.assetId,
          sleeves: const {IncomeStrategySleeveKind.leapsCall},
        ),
      );
    }

    return IncomeStrategySleeveContribution(
      asset: asset,
      snapshot: IncomeStrategySleeveSnapshot(
        kind: IncomeStrategySleeveKind.leapsCall,
        status: open.isEmpty ? 'resolved' : 'open',
        realizedResult: realized,
        projectedCash: Decimal.zero,
        capitalAtRisk: openCost,
        marketValue: hasCompleteMark ? marketValue : null,
        deltaEquivalentShares: hasCompleteDelta ? delta : null,
        cashFlows: List.unmodifiable(flows),
        risks: List.unmodifiable(risks),
        facts: <String, Object?>{
          'open_count': open.length,
          'open_cost': openCost,
          'positions': List<LeapsCallPosition>.unmodifiable(positions),
        },
      ),
    );
  }
}
