import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_plan.dart';
import 'package:naviwealth/features/finance/options_income/application/leaps_scan_targets.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';

void main() {
  test('LEAPS-enabled plans become targets; open cost reduces budget', () {
    final targets = buildLeapsScanTargets(
      plans: [
        _plan(symbol: 'QQQ', leapsEnabled: true, maxCost: '10000'),
        _plan(symbol: 'TQQQ', leapsEnabled: false),
      ],
      positions: [_openLeaps(symbol: 'QQQ', entryDebit: '3000')],
    );

    final target = targets.single;
    expect(target.symbol, 'QQQ');
    // entryDebit is the full per-contract cost: 3000 committed → 7000 left.
    expect(target.budgetRemaining, Money.parse('7000', 'USD'));
    expect(target.groupFundingPool, isNull);
  });

  test('budget floors at zero and missing max_cost means unbounded', () {
    final targets = buildLeapsScanTargets(
      plans: [
        _plan(symbol: 'QQQ', leapsEnabled: true, maxCost: '1000'),
        _plan(symbol: 'SPY', leapsEnabled: true),
      ],
      positions: [_openLeaps(symbol: 'QQQ', entryDebit: '3000')],
    );

    expect(
      targets.singleWhere((t) => t.symbol == 'QQQ').budgetRemaining,
      Money.parse('0', 'USD'),
    );
    expect(
      targets.singleWhere((t) => t.symbol == 'SPY').budgetRemaining,
      isNull,
    );
  });
}

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 7, 26),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
);

IncomeStrategyPlan _plan({
  required String symbol,
  required bool leapsEnabled,
  String? maxCost,
}) => IncomeStrategyPlan(
  id: 'plan-$symbol',
  assetId: 'nasdaq:$symbol',
  symbol: symbol,
  market: 'nasdaq',
  currency: 'USD',
  sleeveIntents: {
    IncomeStrategySleeveKind.leapsCall: IncomeStrategySleeveIntent(
      kind: IncomeStrategySleeveKind.leapsCall,
      enabled: leapsEnabled,
      settings: {
        if (maxCost != null)
          LeapsIncomeStrategySettings.maxCost: IncomeStrategyDecimalSetting(
            Decimal.parse(maxCost),
          ),
      },
    ),
  },
  capitalBudget: null,
  annualIncomeTarget: null,
  maxPositionWeight: null,
  notes: null,
  sync: _meta(),
);

LeapsCallPosition _openLeaps({
  required String symbol,
  required String entryDebit,
}) => LeapsCallPosition(
  underlyingAssetId: 'nasdaq:$symbol',
  id: 'leaps-$symbol',
  symbol: symbol,
  optionSymbol: '${symbol}280121C00200000',
  openedAt: DateTime.utc(2026, 7, 1),
  expirationAt: DateTime.utc(2028, 1, 21),
  closedAt: null,
  strikePrice: Decimal.fromInt(200),
  entryDebit: Decimal.parse(entryDebit),
  exitCredit: null,
  fees: Decimal.zero,
  currency: 'USD',
  contractSize: 100,
  contractQuantity: 1,
  status: LeapsCallStatus.open,
  currentMark: null,
  currentDelta: null,
  markedAt: null,
  brokerageAccountId: null,
  notes: null,
  sync: _meta(),
);
