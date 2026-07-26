import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

import 'income_strategy_asset_resolver.dart';

class DividendIncomeSleeveDetails implements IncomeStrategySleeveDetails {
  const DividendIncomeSleeveDetails({
    required this.ttmGross,
    required this.ytdNet,
    required this.withholdingYtd,
  });

  final IncomeStrategyMoneyMetric ttmGross;
  final IncomeStrategyMoneyMetric ytdNet;
  final IncomeStrategyMoneyMetric withholdingYtd;
}

class DividendIncomeSleeveAdapter {
  const DividendIncomeSleeveAdapter();

  List<IncomeStrategySleeveContribution> build({
    required DividendCenterSnapshot center,
    required Map<String, HoldingSnapshot> holdings,
    required IncomeStrategyAssetResolver assets,
    required DateTime asOf,
    Iterable<String> intendedAssetIds = const [],
  }) {
    final clock = asOf.toUtc();
    final periodStart = DateTime.utc(clock.year);
    final eventsByAsset = <String, List<DividendCenterEvent>>{};
    for (final event in center.events) {
      eventsByAsset
          .putIfAbsent(event.assetId, () => <DividendCenterEvent>[])
          .add(event);
    }

    // A holding alone is not a dividend strategy. Include an asset only when
    // there is dividend evidence or the user explicitly enabled the module.
    final assetIds = <String>{...eventsByAsset.keys, ...intendedAssetIds};
    return [
      for (final assetId in assetIds)
        _buildOne(
          assetId: assetId,
          events: eventsByAsset[assetId] ?? const [],
          holding: holdings[assetId],
          center: center,
          assets: assets,
          periodStart: periodStart,
          asOf: clock,
        ),
    ];
  }

  IncomeStrategySleeveContribution _buildOne({
    required String assetId,
    required List<DividendCenterEvent> events,
    required HoldingSnapshot? holding,
    required DividendCenterSnapshot center,
    required IncomeStrategyAssetResolver assets,
    required DateTime periodStart,
    required DateTime asOf,
  }) {
    var ttmGross = Decimal.zero;
    var ytdGross = Decimal.zero;
    var ytdWithholding = Decimal.zero;
    final flows = <IncomeStrategyCashFlow>[];
    for (final event in events) {
      ttmGross += event.grossInBase;
      if (event.event.date.isBefore(periodStart) ||
          event.event.date.isAfter(asOf)) {
        continue;
      }
      ytdGross += event.grossInBase;
      ytdWithholding += event.withholdingInBase;
      flows.add(
        IncomeStrategyCashFlow(
          id: 'dividend:${event.event.journalEntryId}:gross',
          assetId: assetId,
          sleeve: IncomeStrategySleeveKind.dividends,
          kind: IncomeStrategyCashFlowKind.dividend,
          state: IncomeStrategyCashFlowState.actual,
          date: event.event.date,
          amount: Money(
            event.event.originalAmount + event.withholdingOriginal,
            event.event.currency,
          ),
          baseAmount: Money(event.grossInBase, center.baseCurrency),
          source: IncomeStrategySourceRef(
            table: 'journal_entries',
            id: event.event.journalEntryId,
          ),
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
            amount: Money(
              -event.withholdingOriginal,
              event.withholdingCurrency,
            ),
            baseAmount: Money(-event.withholdingInBase, center.baseCurrency),
            source: IncomeStrategySourceRef(
              table: 'journal_entries',
              id: event.event.journalEntryId,
            ),
          ),
        );
      }
    }
    final ytdNet = ytdGross - ytdWithholding;
    final capital = IncomeStrategyMoneyMetric(
      value: Money(
        holding?.marketValueInBase ?? Decimal.zero,
        center.baseCurrency,
      ),
      quality: holding == null
          ? IncomeStrategyMetricQuality.unavailable
          : IncomeStrategyMetricQuality.complete,
    );
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
            : 'planned',
        periodStart: periodStart,
        asOf: asOf,
        realizedIncome: IncomeStrategyMoneyMetric(
          value: Money(ytdNet, center.baseCurrency),
        ),
        realizedResult: IncomeStrategyMoneyMetric(
          value: Money(ytdNet, center.baseCurrency),
        ),
        projectedCash: IncomeStrategyMoneyMetric.zero(center.baseCurrency),
        exposure: IncomeStrategyExposure(
          capitalAtRisk: capital,
          marketValue: capital,
          deltaEquivalentShares: holding?.quantity,
          holdingQuantity: holding?.quantity,
          holdingWeight: holding?.weight,
        ),
        cashFlows: List.unmodifiable(flows),
        risks: const [],
        details: DividendIncomeSleeveDetails(
          ttmGross: IncomeStrategyMoneyMetric(
            value: Money(ttmGross, center.baseCurrency),
          ),
          ytdNet: IncomeStrategyMoneyMetric(
            value: Money(ytdNet, center.baseCurrency),
          ),
          withholdingYtd: IncomeStrategyMoneyMetric(
            value: Money(ytdWithholding, center.baseCurrency),
          ),
        ),
      ),
    );
  }
}
