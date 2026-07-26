import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/income_strategy/application/income_strategy_asset_resolver.dart';
import 'package:naviwealth/features/finance/income_strategy/application/income_strategy_valuation.dart';
import 'package:naviwealth/features/finance/income_strategy/application/leaps_income_sleeve_adapter.dart';
import 'package:naviwealth/features/finance/income_strategy/application/wheel_income_sleeve_adapter.dart';
import 'package:naviwealth/features/finance/income_strategy/application/wheel_strategy_view.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_assembler.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_plan.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';

/// Cross-underlying wheel view: a TQQQ wheel and a QQQ LEAPS call paired
/// through an explicit strategy group render as one view with a real
/// coverage ratio.
void main() {
  test('explicit group merges TQQQ wheel and QQQ LEAPS into one view', () {
    final assets = IncomeStrategyAssetResolver(const []);
    final converter = FxRateCurrencyConverter(InMemoryFxRateLookup(const []));
    final asOf = DateTime.utc(2026, 7, 26);
    final valuation = IncomeStrategyValuation(
      baseCurrency: 'USD',
      converter: converter,
      asOf: asOf,
    );
    final views = buildWheelStrategyViews(
      const IncomeStrategyAssembler().assemble(
        baseCurrency: 'USD',
        asOf: asOf,
        converter: converter,
        plans: [
          _plan(symbol: 'TQQQ', sleeve: IncomeStrategySleeveKind.wheel),
          _plan(symbol: 'QQQ', sleeve: IncomeStrategySleeveKind.leapsCall),
        ],
        rules: const [],
        contributions: [
          ...const WheelIncomeSleeveAdapter().buildFromEntries(
            entries: [_expiredPut(symbol: 'TQQQ', credit: '120')],
            assets: assets,
            valuation: valuation,
          ),
          ...const LeapsIncomeSleeveAdapter().build(
            positions: [_openLeaps(symbol: 'QQQ', entryDebit: '1000')],
            assets: assets,
            valuation: valuation,
          ),
        ],
      ),
    );

    final view = views.single;
    expect(view.label, 'QQQ enhanced');
    expect(view.group.isExplicit, isTrue);
    expect(view.wheels.single.lifecycle.symbol, 'TQQQ');
    expect(view.positions.single.symbol, 'QQQ');
    expect(view.openLeapsCost, Decimal.parse('1000'));
    // Wheel income 120 over LEAPS cost 1000.
    expect(view.wheelIncomeCoverageRatio, Decimal.parse('0.12'));
    // Exactly one LEAPS underlying — delta may merge.
    expect(view.deltaEquivalentShares, Decimal.parse('65'));
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
  required IncomeStrategySleeveKind sleeve,
}) => IncomeStrategyPlan(
  id: 'plan-$symbol',
  assetId: 'nasdaq:$symbol',
  symbol: symbol,
  market: 'nasdaq',
  currency: 'USD',
  sleeveIntents: {
    sleeve: IncomeStrategySleeveIntent(kind: sleeve, enabled: true),
  },
  capitalBudget: null,
  annualIncomeTarget: null,
  maxPositionWeight: null,
  notes: null,
  groupId: 'g1',
  groupLabel: 'QQQ enhanced',
  sync: _meta(),
);

TradeJournalEntry _expiredPut({
  required String symbol,
  required String credit,
}) => TradeJournalEntry(
  underlyingAssetId: 'nasdaq:$symbol',
  id: 'entry-$symbol',
  strategy: OptionsStrategyKind.cashSecuredPut,
  symbol: symbol,
  optionSymbol: '$symbol-OPT',
  openedAt: DateTime.utc(2026, 5, 1),
  closedAt: DateTime.utc(2026, 5, 15),
  entryCredit: Decimal.parse(credit),
  exitDebit: Decimal.zero,
  realizedPnl: null,
  currency: 'USD',
  status: TradeJournalStatus.expired,
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
  currentDelta: Decimal.parse('0.65'),
  markedAt: null,
  brokerageAccountId: null,
  notes: null,
  sync: _meta(),
);
