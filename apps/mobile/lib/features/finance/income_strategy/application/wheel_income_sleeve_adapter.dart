import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';
import 'package:naviwealth/features/finance/options_income/domain/wheel_lifecycle.dart';

import 'income_strategy_asset_resolver.dart';
import 'income_strategy_valuation.dart';

class WheelIncomeSleeveDetails implements IncomeStrategySleeveDetails {
  const WheelIncomeSleeveDetails({required this.lifecycle});

  final WheelLifecycle lifecycle;
}

class WheelIncomeSleeveAdapter {
  const WheelIncomeSleeveAdapter();

  List<IncomeStrategySleeveContribution> buildFromEntries({
    required Iterable<TradeJournalEntry> entries,
    required IncomeStrategyAssetResolver assets,
    required IncomeStrategyValuation valuation,
  }) {
    final grouped =
        <
          String,
          ({IncomeStrategyAsset asset, List<TradeJournalEntry> entries})
        >{};
    for (final journalEntry in entries) {
      final asset = assets.fromAssetId(
        journalEntry.underlyingAssetId,
        fallbackCurrency: journalEntry.currency,
        fallbackLabel: journalEntry.symbol,
      );
      grouped
          .putIfAbsent(
            asset.assetId,
            () => (asset: asset, entries: <TradeJournalEntry>[]),
          )
          .entries
          .add(journalEntry);
    }
    return [
      for (final group in grouped.values)
        _buildOne(
          asset: group.asset,
          entries: group.entries,
          valuation: valuation,
        ),
    ];
  }

  IncomeStrategySleeveContribution _buildOne({
    required IncomeStrategyAsset asset,
    required List<TradeJournalEntry> entries,
    required IncomeStrategyValuation valuation,
  }) {
    final lifecycle = buildWheelLifecycle(
      symbol: asset.symbol,
      currency: entries.first.currency,
      entries: entries,
    );
    final periodStart = DateTime.utc(valuation.asOf.toUtc().year);
    var assignment = IncomeStrategyMoneyMetric.zero(valuation.baseCurrency);
    var realized = IncomeStrategyMoneyMetric.zero(valuation.baseCurrency);
    final risks = <IncomeStrategyRisk>[];
    final cashFlows = <IncomeStrategyCashFlow>[];

    for (final entry in lifecycle.openPositions) {
      if (entry.strategy == OptionsStrategyKind.cashSecuredPut) {
        final strike = entry.strikePrice;
        if (strike != null) {
          assignment += valuation.metric(
            Money(
              strike *
                  Decimal.fromInt(entry.effectiveContractSize) *
                  Decimal.fromInt(entry.contractQuantity),
              entry.currency,
            ),
          );
        }
      }
      final expiration = entry.expirationAt;
      if (expiration != null &&
          expiration.toUtc().difference(valuation.asOf.toUtc()).inDays <= 14) {
        risks.add(
          IncomeStrategyRisk(
            code: IncomeStrategyRiskCode.expirationNear,
            severity: IncomeStrategyRiskSeverity.warning,
            assetId: asset.assetId,
            sleeves: {IncomeStrategySleeveKind.wheel},
            evidence: {
              'option_symbol': entry.optionSymbol,
              'expiration_at': expiration.toIso8601String(),
            },
          ),
        );
      }
    }

    for (final entry in lifecycle.entries) {
      if (entry.trackedNetPnl case final tracked?) {
        final date = entry.closedAt ?? entry.openedAt;
        final original = Money(tracked, entry.currency);
        final base = valuation.tryToBase(original, on: date);
        if (!date.isBefore(periodStart) &&
            !date.isAfter(valuation.asOf) &&
            base != null) {
          realized += IncomeStrategyMoneyMetric(value: base);
        } else if (!date.isBefore(periodStart) &&
            !date.isAfter(valuation.asOf) &&
            base == null) {
          realized += IncomeStrategyMoneyMetric.zero(
            valuation.baseCurrency,
            quality: IncomeStrategyMetricQuality.partial,
          );
        }
        cashFlows.add(
          IncomeStrategyCashFlow(
            id: 'wheel:${entry.id}:realized',
            assetId: asset.assetId,
            sleeve: IncomeStrategySleeveKind.wheel,
            kind: IncomeStrategyCashFlowKind.optionRealized,
            state: IncomeStrategyCashFlowState.actual,
            date: date,
            amount: original,
            baseAmount: base,
            source: IncomeStrategySourceRef(
              table: 'options_trade_journal',
              id: entry.id,
            ),
          ),
        );
      }
    }

    if (assignment.quality == IncomeStrategyMetricQuality.unavailable ||
        realized.quality == IncomeStrategyMetricQuality.partial) {
      risks.add(
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.missingFxRate,
          severity: IncomeStrategyRiskSeverity.warning,
          assetId: asset.assetId,
          sleeves: {IncomeStrategySleeveKind.wheel},
        ),
      );
    }

    return IncomeStrategySleeveContribution(
      asset: asset,
      snapshot: IncomeStrategySleeveSnapshot(
        kind: IncomeStrategySleeveKind.wheel,
        status: lifecycle.stage.name,
        periodStart: periodStart,
        asOf: valuation.asOf.toUtc(),
        realizedIncome: realized,
        realizedResult: realized,
        projectedCash: IncomeStrategyMoneyMetric.zero(valuation.baseCurrency),
        exposure: IncomeStrategyExposure(
          capitalAtRisk: assignment,
          assignmentObligation: assignment,
          hasOpenShortPut: lifecycle.openPositions.any(
            (entry) => entry.strategy == OptionsStrategyKind.cashSecuredPut,
          ),
          hasOpenCoveredCall: lifecycle.openPositions.any(
            (entry) => entry.strategy == OptionsStrategyKind.coveredCall,
          ),
        ),
        cashFlows: List.unmodifiable(cashFlows),
        risks: List.unmodifiable(risks),
        details: WheelIncomeSleeveDetails(lifecycle: lifecycle),
      ),
    );
  }
}
