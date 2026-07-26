import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';
import 'package:naviwealth/features/finance/options_income/domain/wheel_lifecycle.dart';

import 'income_strategy_asset_resolver.dart';

class WheelIncomeSleeveAdapter {
  const WheelIncomeSleeveAdapter();

  List<IncomeStrategySleeveContribution> buildFromEntries({
    required Iterable<TradeJournalEntry> entries,
    required IncomeStrategyAssetResolver assets,
    DateTime? now,
  }) {
    final bySymbol = <String, List<TradeJournalEntry>>{};
    for (final entry in entries) {
      bySymbol
          .putIfAbsent(entry.symbol, () => <TradeJournalEntry>[])
          .add(entry);
    }
    return build(
      lifecycles: [
        for (final entry in bySymbol.entries)
          buildWheelLifecycle(
            symbol: entry.key,
            currency: entry.value.first.currency,
            entries: entry.value,
          ),
      ],
      assets: assets,
      now: now,
    );
  }

  List<IncomeStrategySleeveContribution> build({
    required Iterable<WheelLifecycle> lifecycles,
    required IncomeStrategyAssetResolver assets,
    DateTime? now,
  }) {
    final clock = (now ?? DateTime.now()).toUtc();
    return [
      for (final lifecycle in lifecycles)
        _buildOne(lifecycle, assets: assets, now: clock),
    ];
  }

  IncomeStrategySleeveContribution _buildOne(
    WheelLifecycle lifecycle, {
    required IncomeStrategyAssetResolver assets,
    required DateTime now,
  }) {
    final first = lifecycle.entries.firstOrNull;
    final asset = assets.fromSymbol(
      symbol: lifecycle.symbol,
      currency: lifecycle.currency,
      marketWire: first?.underlyingMarket,
    );
    var assignmentValue = Decimal.zero;
    final risks = <IncomeStrategyRisk>[];
    for (final entry in lifecycle.openPositions) {
      if (entry.strategy == OptionsStrategyKind.cashSecuredPut) {
        final strike = entry.strikePrice;
        if (strike != null) {
          assignmentValue +=
              strike *
              Decimal.fromInt(entry.effectiveContractSize) *
              Decimal.fromInt(entry.contractQuantity);
        }
      }
      final expiration = entry.expirationAt;
      if (expiration != null &&
          expiration.toUtc().difference(now).inDays <= 14) {
        risks.add(
          IncomeStrategyRisk(
            code: IncomeStrategyRiskCode.expirationNear,
            severity: IncomeStrategyRiskSeverity.warning,
            assetId: asset.assetId,
            sleeves: const {IncomeStrategySleeveKind.wheel},
            evidence: {
              'option_symbol': entry.optionSymbol,
              'expiration_at': expiration.toIso8601String(),
            },
          ),
        );
      }
    }
    final cashFlows = [
      for (final entry in lifecycle.entries)
        if (entry.trackedNetPnl case final realized?)
          IncomeStrategyCashFlow(
            id: 'wheel:${entry.id}:realized',
            assetId: asset.assetId,
            sleeve: IncomeStrategySleeveKind.wheel,
            kind: IncomeStrategyCashFlowKind.optionRealized,
            state: IncomeStrategyCashFlowState.actual,
            date: entry.closedAt ?? entry.openedAt,
            amount: realized,
            currency: entry.currency,
            sourceTable: 'options_trade_journal',
            sourceId: entry.id,
            hasCompleteEvidence: true,
          ),
    ];
    return IncomeStrategySleeveContribution(
      asset: asset,
      snapshot: IncomeStrategySleeveSnapshot(
        kind: IncomeStrategySleeveKind.wheel,
        status: lifecycle.stage.name,
        realizedResult: lifecycle.cumulativeIncome,
        projectedCash: Decimal.zero,
        capitalAtRisk: assignmentValue,
        marketValue: null,
        deltaEquivalentShares: null,
        cashFlows: List.unmodifiable(cashFlows),
        risks: List.unmodifiable(risks),
        facts: <String, Object?>{
          'stage': lifecycle.stage.name,
          'open_count': lifecycle.openPositions.length,
          'assignment_value': assignmentValue,
          'has_open_short_put': lifecycle.openPositions.any(
            (entry) => entry.strategy == OptionsStrategyKind.cashSecuredPut,
          ),
          'has_open_covered_call': lifecycle.openPositions.any(
            (entry) => entry.strategy == OptionsStrategyKind.coveredCall,
          ),
          'lifecycle': lifecycle,
        },
      ),
    );
  }
}
