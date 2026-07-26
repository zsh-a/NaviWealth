import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

import 'income_strategy_asset_resolver.dart';

class DividendIncomeSleeveAdapter {
  const DividendIncomeSleeveAdapter();

  List<IncomeStrategySleeveContribution> build({
    required DividendCenterSnapshot center,
    required Map<String, HoldingSnapshot> holdings,
    required IncomeStrategyAssetResolver assets,
  }) {
    final eventsByAsset = <String, List<DividendCenterEvent>>{};
    for (final event in center.events) {
      eventsByAsset
          .putIfAbsent(event.assetId, () => <DividendCenterEvent>[])
          .add(event);
    }
    final assetIds = <String>{...eventsByAsset.keys, ...holdings.keys};
    return [
      for (final assetId in assetIds)
        _buildOne(
          assetId: assetId,
          events: eventsByAsset[assetId] ?? const [],
          holding: holdings[assetId],
          center: center,
          assets: assets,
        ),
    ];
  }

  IncomeStrategySleeveContribution _buildOne({
    required String assetId,
    required List<DividendCenterEvent> events,
    required HoldingSnapshot? holding,
    required DividendCenterSnapshot center,
    required IncomeStrategyAssetResolver assets,
  }) {
    var gross = Decimal.zero;
    var withholding = Decimal.zero;
    final flows = <IncomeStrategyCashFlow>[];
    for (final event in events) {
      gross += event.grossInBase;
      withholding += event.withholdingInBase;
      flows.add(
        IncomeStrategyCashFlow(
          id: 'dividend:${event.event.journalEntryId}:gross',
          assetId: assetId,
          sleeve: IncomeStrategySleeveKind.dividends,
          kind: IncomeStrategyCashFlowKind.dividend,
          state: IncomeStrategyCashFlowState.actual,
          date: event.event.date,
          amount: event.grossInBase,
          currency: center.baseCurrency,
          sourceTable: 'journal_entries',
          sourceId: event.event.journalEntryId,
          hasCompleteEvidence: true,
        ),
      );
      if (event.withholdingInBase > Decimal.zero) {
        flows.add(
          IncomeStrategyCashFlow(
            id: 'dividend:${event.event.journalEntryId}:withholding',
            assetId: assetId,
            sleeve: IncomeStrategySleeveKind.dividends,
            kind: IncomeStrategyCashFlowKind.dividendWithholding,
            state: IncomeStrategyCashFlowState.actual,
            date: event.event.date,
            amount: -event.withholdingInBase,
            currency: center.baseCurrency,
            sourceTable: 'journal_entries',
            sourceId: event.event.journalEntryId,
            hasCompleteEvidence: true,
          ),
        );
      }
    }
    final net = gross - withholding;
    return IncomeStrategySleeveContribution(
      asset: assets.fromAssetId(
        assetId,
        fallbackCurrency: holding?.assetCurrency ?? center.baseCurrency,
        fallbackLabel: events.firstOrNull?.assetLabel,
      ),
      snapshot: IncomeStrategySleeveSnapshot(
        kind: IncomeStrategySleeveKind.dividends,
        status: holding != null && holding.quantity > Decimal.zero
            ? 'holding'
            : 'history_only',
        realizedResult: net,
        projectedCash: Decimal.zero,
        capitalAtRisk: holding?.marketValueInBase ?? Decimal.zero,
        marketValue: holding?.marketValueInBase,
        deltaEquivalentShares: holding?.quantity,
        cashFlows: List.unmodifiable(flows),
        risks: const [],
        facts: <String, Object?>{
          'holding_quantity': holding?.quantity,
          'holding_weight': holding?.weight,
          'ttm_gross': gross,
          'ttm_net': net,
          'withholding': withholding,
        },
      ),
    );
  }
}
