import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';

import 'income_strategy_asset_resolver.dart';
import 'income_strategy_valuation.dart';

class LeapsIncomeSleeveDetails implements IncomeStrategySleeveDetails {
  const LeapsIncomeSleeveDetails({required this.positions});

  final List<LeapsCallPosition> positions;
}

class LeapsIncomeSleeveAdapter {
  const LeapsIncomeSleeveAdapter();

  List<IncomeStrategySleeveContribution> build({
    required Iterable<LeapsCallPosition> positions,
    required IncomeStrategyAssetResolver assets,
    required IncomeStrategyValuation valuation,
  }) {
    final grouped =
        <
          String,
          ({IncomeStrategyAsset asset, List<LeapsCallPosition> positions})
        >{};
    for (final position in positions) {
      final asset = assets.fromAssetId(
        position.underlyingAssetId,
        fallbackCurrency: position.currency,
        fallbackLabel: position.symbol,
      );
      grouped
          .putIfAbsent(
            asset.assetId,
            () => (asset: asset, positions: <LeapsCallPosition>[]),
          )
          .positions
          .add(position);
    }
    return [
      for (final group in grouped.values)
        _buildOne(
          asset: group.asset,
          positions: group.positions,
          valuation: valuation,
        ),
    ];
  }

  IncomeStrategySleeveContribution _buildOne({
    required IncomeStrategyAsset asset,
    required List<LeapsCallPosition> positions,
    required IncomeStrategyValuation valuation,
  }) {
    final open = positions.where((position) => position.isOpen).toList();
    final periodStart = DateTime.utc(valuation.asOf.toUtc().year);
    var openCost = IncomeStrategyMoneyMetric.zero(valuation.baseCurrency);
    var marketValue = IncomeStrategyMoneyMetric.zero(valuation.baseCurrency);
    var realized = IncomeStrategyMoneyMetric.zero(valuation.baseCurrency);
    var delta = Decimal.zero;
    var hasCompleteMark = open.isNotEmpty;
    var hasCompleteDelta = open.isNotEmpty;
    var hasMissingFx = false;
    final risks = <IncomeStrategyRisk>[];
    final flows = <IncomeStrategyCashFlow>[];

    for (final position in positions) {
      final purchase = Money(-position.grossEntryCost, position.currency);
      final purchaseBase = valuation.tryToBase(purchase, on: position.openedAt);
      flows.add(
        IncomeStrategyCashFlow(
          id: 'leaps:${position.id}:purchase',
          assetId: asset.assetId,
          sleeve: IncomeStrategySleeveKind.leapsCall,
          kind: IncomeStrategyCashFlowKind.leapsPurchase,
          state: IncomeStrategyCashFlowState.actual,
          date: position.openedAt,
          amount: purchase,
          baseAmount: purchaseBase,
          source: IncomeStrategySourceRef(
            table: 'options_leaps_call_positions',
            id: position.id,
          ),
        ),
      );
      if (purchaseBase == null) hasMissingFx = true;

      final proceeds = position.grossExitProceeds;
      if (proceeds != null) {
        final saleDate = position.closedAt ?? position.expirationAt;
        final sale = Money(proceeds, position.currency);
        final saleBase = valuation.tryToBase(sale, on: saleDate);
        flows.add(
          IncomeStrategyCashFlow(
            id: 'leaps:${position.id}:sale',
            assetId: asset.assetId,
            sleeve: IncomeStrategySleeveKind.leapsCall,
            kind: IncomeStrategyCashFlowKind.leapsSale,
            state: IncomeStrategyCashFlowState.actual,
            date: saleDate,
            amount: sale,
            baseAmount: saleBase,
            source: IncomeStrategySourceRef(
              table: 'options_leaps_call_positions',
              id: position.id,
            ),
          ),
        );
        if (saleBase == null) hasMissingFx = true;
      }
      if (position.status == LeapsCallStatus.exercised) {
        final exerciseDate = position.closedAt ?? position.expirationAt;
        final exercise = Money(
          -position.strikePrice *
              Decimal.fromInt(
                position.contractSize * position.contractQuantity,
              ),
          position.currency,
        );
        final exerciseBase = valuation.tryToBase(exercise, on: exerciseDate);
        flows.add(
          IncomeStrategyCashFlow(
            id: 'leaps:${position.id}:exercise',
            assetId: asset.assetId,
            sleeve: IncomeStrategySleeveKind.leapsCall,
            kind: IncomeStrategyCashFlowKind.leapsExercise,
            state: IncomeStrategyCashFlowState.actual,
            date: exerciseDate,
            amount: exercise,
            baseAmount: exerciseBase,
            source: IncomeStrategySourceRef(
              table: 'options_leaps_call_positions',
              id: position.id,
            ),
          ),
        );
        if (exerciseBase == null) hasMissingFx = true;
      }

      if (!position.isOpen) {
        final resolvedAt = position.closedAt ?? position.expirationAt;
        final result = position.realizedPnl;
        if (result != null &&
            !resolvedAt.isBefore(periodStart) &&
            !resolvedAt.isAfter(valuation.asOf)) {
          realized += valuation.metric(
            Money(result, position.currency),
            on: resolvedAt,
          );
        }
        continue;
      }

      openCost += valuation.metric(
        Money(position.grossEntryCost, position.currency),
      );
      final markedValue = position.marketValue;
      if (markedValue == null) {
        hasCompleteMark = false;
      } else {
        marketValue += valuation.metric(
          Money(markedValue, position.currency),
          on: position.markedAt,
        );
      }
      final deltaShares = position.deltaEquivalentShares;
      if (deltaShares == null) {
        hasCompleteDelta = false;
      } else {
        delta += deltaShares;
      }
      if (position.expirationAt
              .toUtc()
              .difference(valuation.asOf.toUtc())
              .inDays <=
          180) {
        risks.add(
          IncomeStrategyRisk(
            code: IncomeStrategyRiskCode.expirationNear,
            severity: IncomeStrategyRiskSeverity.warning,
            assetId: asset.assetId,
            sleeves: {IncomeStrategySleeveKind.leapsCall},
            evidence: {
              'option_symbol': position.optionSymbol,
              'expiration_at': position.expirationAt.toIso8601String(),
            },
          ),
        );
      }
      final markedAt = position.markedAt;
      if (markedAt != null &&
          valuation.asOf.toUtc().difference(markedAt.toUtc()).inDays > 7) {
        risks.add(
          IncomeStrategyRisk(
            code: IncomeStrategyRiskCode.staleValuation,
            severity: IncomeStrategyRiskSeverity.info,
            assetId: asset.assetId,
            sleeves: {IncomeStrategySleeveKind.leapsCall},
            evidence: {
              'option_symbol': position.optionSymbol,
              'marked_at': markedAt.toIso8601String(),
            },
          ),
        );
      }
    }
    if (open.isNotEmpty && !hasCompleteMark) {
      marketValue = IncomeStrategyMoneyMetric(
        value: marketValue.value,
        quality: IncomeStrategyMetricQuality.partial,
      );
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.missingMarketValue,
          severity: IncomeStrategyRiskSeverity.info,
          assetId: asset.assetId,
          sleeves: {IncomeStrategySleeveKind.leapsCall},
        ),
      );
    }
    if (open.isNotEmpty && !hasCompleteDelta) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.missingDelta,
          severity: IncomeStrategyRiskSeverity.info,
          assetId: asset.assetId,
          sleeves: {IncomeStrategySleeveKind.leapsCall},
        ),
      );
    }
    if (hasMissingFx ||
        openCost.quality == IncomeStrategyMetricQuality.unavailable ||
        marketValue.quality == IncomeStrategyMetricQuality.unavailable) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.missingFxRate,
          severity: IncomeStrategyRiskSeverity.warning,
          assetId: asset.assetId,
          sleeves: {IncomeStrategySleeveKind.leapsCall},
        ),
      );
    }

    return IncomeStrategySleeveContribution(
      asset: asset,
      snapshot: IncomeStrategySleeveSnapshot(
        kind: IncomeStrategySleeveKind.leapsCall,
        status: open.isEmpty ? 'resolved' : 'open',
        periodStart: periodStart,
        asOf: valuation.asOf.toUtc(),
        realizedIncome: IncomeStrategyMoneyMetric.zero(valuation.baseCurrency),
        realizedResult: realized,
        projectedCash: IncomeStrategyMoneyMetric.zero(valuation.baseCurrency),
        exposure: IncomeStrategyExposure(
          capitalAtRisk: openCost,
          marketValue: open.isEmpty ? null : marketValue,
          deltaEquivalentShares: hasCompleteDelta ? delta : null,
        ),
        cashFlows: List.unmodifiable(flows),
        risks: List.unmodifiable(risks),
        details: LeapsIncomeSleeveDetails(
          positions: List<LeapsCallPosition>.unmodifiable(positions),
        ),
      ),
    );
  }
}
