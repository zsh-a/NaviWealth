import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_event.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/journal_entry.dart';
import 'package:naviwealth/features/finance/data/domain/posting.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

void main() {
  test('100 dividend JE fixture produces exact TTM gross and withholding', () {
    final entries = <String, JournalEntryWithPostings>{};
    final events = <CashFlowEvent>[];
    for (var i = 0; i < 100; i++) {
      final assetId = i < 60 ? 'us:AAPL' : 'us:VOO';
      final id = 'div-$i';
      final date = DateTime.utc(2026, 5, 1).subtract(Duration(days: i));
      entries[id] = _dividendEntry(
        id: id,
        date: date,
        assetId: assetId,
        net: '9',
        gross: '10',
        withholding: '1',
      );
      events.add(_event(id: id, date: date, amount: '9'));
    }

    final snapshot = buildDividendCenterSnapshot(
      dividendEvents: events,
      entriesById: entries,
      accountsById: _accounts,
      holdings: {
        'us:AAPL': _holding('us:AAPL', costBasis: '10000'),
        'us:VOO': _holding('us:VOO', costBasis: '5000'),
      },
      baseCurrency: 'USD',
      now: DateTime.utc(2026, 5, 17),
    );

    expect(snapshot.ttmGross, Decimal.fromInt(1000));
    expect(snapshot.yearToDateGross, Decimal.fromInt(1000));
    expect(snapshot.ttmWithholding, Decimal.fromInt(100));
    expect(snapshot.ranking.first.assetId, 'us:AAPL');
    expect(snapshot.ranking.first.ttmGrossInBase, Decimal.fromInt(600));
    expect(snapshot.ranking.first.portfolioShare, 0.6);
    expect(snapshot.ranking.first.yieldOnCost, 0.06);
  });

  test('base-currency recomputation can change the holding ranking', () {
    final entries = {
      'aapl': _dividendEntry(
        id: 'aapl',
        date: DateTime.utc(2026, 5, 1),
        assetId: 'us:AAPL',
        net: '90',
        gross: '100',
        withholding: '10',
      ),
      'moutai': _dividendEntry(
        id: 'moutai',
        date: DateTime.utc(2026, 5, 2),
        assetId: 'cn:600519',
        net: '800',
        gross: '800',
        withholding: '0',
        currency: 'CNY',
      ),
    };

    final cny = buildDividendCenterSnapshot(
      dividendEvents: [
        _event(id: 'aapl', date: DateTime.utc(2026, 5, 1), amount: '630'),
        _event(
          id: 'moutai',
          date: DateTime.utc(2026, 5, 2),
          amount: '800',
          currency: 'CNY',
        ),
      ],
      entriesById: entries,
      accountsById: _accounts,
      holdings: const {},
      baseCurrency: 'CNY',
      now: DateTime.utc(2026, 5, 17),
      convertToBaseAmount: (amount, currency, _) =>
          currency == 'USD' ? amount * Decimal.fromInt(7) : amount,
    );

    final usd = buildDividendCenterSnapshot(
      dividendEvents: [
        _event(id: 'aapl', date: DateTime.utc(2026, 5, 1), amount: '90'),
        _event(
          id: 'moutai',
          date: DateTime.utc(2026, 5, 2),
          amount: '80',
          currency: 'CNY',
        ),
      ],
      entriesById: entries,
      accountsById: _accounts,
      holdings: const {},
      baseCurrency: 'USD',
      now: DateTime.utc(2026, 5, 17),
      convertToBaseAmount: (amount, currency, _) => currency == 'CNY'
          ? (amount / Decimal.fromInt(10)).toDecimal()
          : amount,
    );

    expect(cny.ranking.first.assetId, 'cn:600519');
    expect(cny.ranking.first.ttmGrossInBase, Decimal.fromInt(800));
    expect(usd.ranking.first.assetId, 'us:AAPL');
    expect(usd.ranking.first.ttmGrossInBase, Decimal.fromInt(100));
  });
}

final _accounts = {
  'cash': _account('cash', 'Brokerage Cash', AccountSide.asset),
  'income': _account('income', 'Dividend Income', AccountSide.income),
  'tax': _account('tax', 'Expense:Tax:Withholding', AccountSide.expense),
};

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'd',
  hlc: Hlc.zero('d'),
);

Account _account(String id, String name, AccountSide side) => Account(
  id: id,
  type: AccountCategory.asset,
  name: name,
  currency: 'USD',
  category: side,
  sync: _meta(),
);

CashFlowEvent _event({
  required String id,
  required DateTime date,
  required String amount,
  String currency = 'USD',
}) {
  final value = Decimal.parse(amount);
  return CashFlowEvent(
    journalEntryId: id,
    date: date,
    kind: CashFlowKind.dividend,
    signedAmount: value,
    originalAmount: value,
    currency: currency,
    accountId: 'cash',
    counterAccountSide: AccountSide.income,
  );
}

JournalEntryWithPostings _dividendEntry({
  required String id,
  required DateTime date,
  required String assetId,
  required String net,
  required String gross,
  required String withholding,
  String currency = 'USD',
}) {
  return JournalEntryWithPostings(
    entry: JournalEntry(
      id: id,
      date: date,
      narration: 'Dividend',
      tagIds: ['asset:$assetId'],
      sync: _meta(),
    ),
    postings: [
      _posting('$id-cash', id, 0, 'cash', net, currency),
      _posting('$id-income', id, 1, 'income', '-$gross', currency),
      _posting('$id-tax', id, 2, 'tax', withholding, currency),
    ],
  );
}

Posting _posting(
  String id,
  String journalEntryId,
  int position,
  String accountId,
  String units,
  String unit,
) => Posting(
  id: id,
  journalEntryId: journalEntryId,
  position: position,
  accountId: accountId,
  units: Decimal.parse(units),
  unit: unit,
  sync: _meta(),
);

HoldingSnapshot _holding(String assetId, {required String costBasis}) {
  final basis = Decimal.parse(costBasis);
  return HoldingSnapshot(
    assetId: assetId,
    quantity: Decimal.fromInt(1),
    costBasisInAssetCurrency: basis,
    marketValueInAssetCurrency: basis,
    assetCurrency: 'USD',
    costBasisInBase: basis,
    marketValueInBase: basis,
    unrealizedPnlInBase: Decimal.zero,
    weight: Decimal.zero,
    baseCurrency: 'USD',
    asOf: DateTime.utc(2026, 5, 17),
  );
}
