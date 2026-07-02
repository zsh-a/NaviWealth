import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_trade_entry_prefills.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/l10n/gen/app_localizations_en.dart';

void main() {
  test('builds trade-entry prefills from rebalance suggestions', () {
    final plan = _plan();
    final l10n = AppLocalizationsEn();
    final drafts = buildRebalanceTradeEntryPrefills(
      plan: plan,
      tradeDate: DateTime.utc(2026, 5, 18),
      noteBuilder: (trade) => l10n.rebalanceExecutionDraftNote(
        trade.isBuy ? l10n.rebalanceBuy : l10n.rebalanceSell,
        trade.category.name,
        trade.amount.amount.toString(),
        trade.amount.currency,
      ),
    );

    expect(drafts, hasLength(2));
    expect(drafts[0].type, TradeType.sell);
    expect(drafts[0].quantity, Decimal.one);
    expect(drafts[0].price, Decimal.parse('1000.25'));
    expect(drafts[0].currency, 'CNY');
    expect(drafts[0].fee, Decimal.parse('1.00025'));
    expect(drafts[0].tax, Decimal.parse('2.00'));
    expect(drafts[0].note, contains('Sell stock'));

    expect(drafts[1].type, TradeType.buy);
    expect(drafts[1].price, Decimal.parse('999.75'));
    expect(drafts[1].fee, Decimal.parse('0.99975'));
    expect(drafts[1].tax, Decimal.zero);
    expect(drafts[1].note, contains('Buy etf'));
  });

  test(
    'allocates fees across all trades and taxes across sell trades only',
    () {
      final drafts = buildRebalanceTradeEntryPrefills(
        plan: _plan(
          trades: [
            SuggestedTrade(
              category: AssetCategory.stock,
              direction: TradeDirection.sell,
              amount: Money(Decimal.parse('100'), 'CNY'),
            ),
            SuggestedTrade(
              category: AssetCategory.etf,
              direction: TradeDirection.sell,
              amount: Money(Decimal.parse('200'), 'CNY'),
            ),
            SuggestedTrade(
              category: AssetCategory.cash,
              direction: TradeDirection.buy,
              amount: Money(Decimal.parse('100'), 'CNY'),
            ),
          ],
          estimatedFees: Money(Decimal.parse('4'), 'CNY'),
          estimatedTaxes: Money(Decimal.parse('3'), 'CNY'),
        ),
        tradeDate: DateTime.utc(2026, 5, 18),
        noteBuilder: (trade) => trade.category.name,
      );

      expect(drafts.map((draft) => draft.fee), [
        Decimal.parse('1.00'),
        Decimal.parse('2.00'),
        Decimal.parse('1.00'),
      ]);
      expect(drafts.map((draft) => draft.tax), [
        Decimal.parse('1.0'),
        Decimal.parse('2.0'),
        Decimal.zero,
      ]);
    },
  );

  test('returns no prefills for an empty rebalance plan', () {
    final drafts = buildRebalanceTradeEntryPrefills(
      plan: _plan(trades: const []),
      tradeDate: DateTime.utc(2026, 5, 18),
      noteBuilder: (_) => 'unused',
    );

    expect(drafts, isEmpty);
  });

  test('allocates zero fees and taxes when trade amounts are zero', () {
    final drafts = buildRebalanceTradeEntryPrefills(
      plan: _plan(
        trades: [
          SuggestedTrade(
            category: AssetCategory.stock,
            direction: TradeDirection.sell,
            amount: Money(Decimal.zero, 'CNY'),
          ),
          SuggestedTrade(
            category: AssetCategory.etf,
            direction: TradeDirection.buy,
            amount: Money(Decimal.zero, 'CNY'),
          ),
        ],
        estimatedFees: Money(Decimal.parse('2'), 'CNY'),
        estimatedTaxes: Money(Decimal.parse('1'), 'CNY'),
      ),
      tradeDate: DateTime.utc(2026, 5, 18),
      noteBuilder: (trade) => trade.category.name,
    );

    expect(drafts.map((draft) => draft.fee), [Decimal.zero, Decimal.zero]);
    expect(drafts.map((draft) => draft.tax), [Decimal.zero, Decimal.zero]);
  });
}

RebalancePlan _plan({
  List<SuggestedTrade>? trades,
  Money? estimatedFees,
  Money? estimatedTaxes,
}) {
  return RebalancePlan(
    target: const TargetAllocation(weights: {}),
    actualWeights: const {},
    drifts: const [],
    trades:
        trades ??
        [
          SuggestedTrade(
            category: AssetCategory.stock,
            direction: TradeDirection.sell,
            amount: Money(Decimal.parse('1000.25'), 'CNY'),
          ),
          SuggestedTrade(
            category: AssetCategory.etf,
            direction: TradeDirection.buy,
            amount: Money(Decimal.parse('999.75'), 'CNY'),
          ),
        ],
    estimatedFees: estimatedFees ?? Money(Decimal.parse('2.00'), 'CNY'),
    estimatedTaxes: estimatedTaxes ?? Money(Decimal.parse('2.00'), 'CNY'),
    driftBeforePct: 0.18,
    driftAfterPct: 0.002,
    totalAssets: Money(Decimal.parse('100000'), 'CNY'),
  );
}
