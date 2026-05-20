import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/rebalance/application/rebalance_trade_entry_prefills.dart';
import 'package:naviwealth/features/rebalance/domain/rebalance_models.dart';
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
}

RebalancePlan _plan() {
  return RebalancePlan(
    target: const TargetAllocation(weights: {}),
    actualWeights: const {},
    drifts: const [],
    trades: [
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
    estimatedFees: Money(Decimal.parse('2.00'), 'CNY'),
    estimatedTaxes: Money(Decimal.parse('2.00'), 'CNY'),
    driftBeforePct: 0.18,
    driftAfterPct: 0.002,
    totalAssets: Money(Decimal.parse('100000'), 'CNY'),
  );
}
