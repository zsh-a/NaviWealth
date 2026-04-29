import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/domain/transaction.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/investment/domain/returns/cash_flow_extractor.dart';

const _user = 'user-1';

Decimal _d(String s) => Decimal.parse(s);

Transaction _tx({
  required String id,
  required TransactionType type,
  required String accountId,
  required String? assetId,
  required Decimal quantity,
  required Decimal price,
  required String currency,
  required DateTime tradeDate,
  Decimal? fee,
  Decimal? tax,
  String owner = _user,
  DateTime? deletedAt,
}) {
  return Transaction(
    id: id,
    accountId: accountId,
    assetId: assetId,
    type: type,
    quantity: quantity,
    price: price,
    currency: currency,
    tradeDate: tradeDate,
    fee: fee,
    tax: tax,
    sync: SyncMeta(
      ownerUserId: owner,
      updatedAt: tradeDate,
      updatedByDevice: 'dev-1',
      hlc: Hlc.zero('node-1'),
      deletedAt: deletedAt,
    ),
  );
}

CashFlowExtractor _extractor({
  String base = 'USD',
  Iterable<FxRate> rates = const [],
}) => CashFlowExtractor(
  converter: FxRateCurrencyConverter(InMemoryFxRateLookup(rates)),
  baseCurrency: base,
);

void main() {
  group('CashFlowExtractor — position scope', () {
    test('buy → outflow including fee + tax', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'tx',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('10'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 5),
            fee: _d('5'),
            tax: _d('1'),
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
        filter: const CashFlowFilter(ownerUserId: _user),
      );
      expect(flows, hasLength(1));
      expect(flows.single.amount, -1006.0); // 10 * 100 + 5 + 1
    });

    test('sell → inflow net of fee + tax', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'tx',
            type: TransactionType.sell,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('10'),
            price: _d('150'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 5),
            fee: _d('3'),
            tax: _d('2'),
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows.single.amount, 1495.0); // 10 * 150 − 3 − 2
    });

    test('cash dividend → inflow net of withholding tax', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'tx',
            type: TransactionType.dividend,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('100'),
            price: _d('0.50'), // $0.50 per share
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 3, 15),
            tax: _d('5'),
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows.single.amount, 45.0); // 100 * 0.5 − 5
    });

    test(
      'deposit / transfer / valuation rows do not produce position flows',
      () {
        final flows = _extractor().extract(
          transactions: [
            for (final type in [
              TransactionType.deposit,
              TransactionType.withdraw,
              TransactionType.transferIn,
              TransactionType.transferOut,
              TransactionType.valuationAdjust,
              TransactionType.split,
              TransactionType.liabilityPayment,
            ])
              _tx(
                id: 'tx-${type.name}',
                type: type,
                accountId: 'a',
                assetId: 'AAPL',
                quantity: _d('1'),
                price: _d('100'),
                currency: 'USD',
                tradeDate: DateTime.utc(2026, 1, 5),
              ),
          ],
          scope: CashFlowScope.position,
          range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
        );
        expect(flows, isEmpty);
      },
    );
  });

  group('CashFlowExtractor — account scope', () {
    test('only deposits / withdrawals / transfers cross the boundary', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'd',
            type: TransactionType.deposit,
            accountId: 'a',
            assetId: null,
            quantity: _d('1'),
            price: _d('5000'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 1),
          ),
          _tx(
            id: 'w',
            type: TransactionType.withdraw,
            accountId: 'a',
            assetId: null,
            quantity: _d('1'),
            price: _d('1000'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 6, 1),
          ),
          _tx(
            // Internal trade — must be excluded at account scope.
            id: 'b',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('10'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 2, 1),
          ),
        ],
        scope: CashFlowScope.account,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      // Two flows — deposit (−5000) and withdraw (+1000).
      expect(flows, hasLength(2));
      final byDate = {for (final f in flows) f.date: f.amount};
      expect(byDate[DateTime.utc(2026, 1, 1)], -5000.0);
      expect(byDate[DateTime.utc(2026, 6, 1)], 1000.0);
    });
  });

  group('CashFlowExtractor — filtering', () {
    test('out-of-range transactions are excluded', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'past',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('1'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2025, 12, 31),
          ),
          _tx(
            id: 'in',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('1'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 6, 1),
          ),
          _tx(
            id: 'future',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('1'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2027, 1, 1, 0, 0, 1), // 1µs after `to`
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows, hasLength(1));
    });

    test('soft-deleted and other-owner transactions are skipped', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'deleted',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('1'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 6, 1),
            deletedAt: DateTime.utc(2026, 6, 2),
          ),
          _tx(
            id: 'other',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('1'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 6, 1),
            owner: 'someone-else',
          ),
          _tx(
            id: 'mine',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('1'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 6, 1),
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
        filter: const CashFlowFilter(ownerUserId: _user),
      );
      expect(flows, hasLength(1));
    });

    test('asset-id filter narrows to a subset', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'aapl',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('1'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 6, 1),
          ),
          _tx(
            id: 'tsla',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'TSLA',
            quantity: _d('1'),
            price: _d('200'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 6, 1),
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
        filter: const CashFlowFilter(assetIds: {'TSLA'}),
      );
      expect(flows, hasLength(1));
      expect(flows.single.amount, -200.0);
    });
  });

  group('CashFlowExtractor — position scope (extra cases)', () {
    test('reinvest tx (DRIP buy leg) → outflow', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'r',
            type: TransactionType.reinvest,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('1'),
            price: _d('80'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 4, 15),
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows.single.amount, -80.0);
    });

    test('asset-tagged fee / tax → outflow', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'f',
            type: TransactionType.fee,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('1'),
            price: _d('12'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 4, 15),
          ),
          _tx(
            id: 't',
            type: TransactionType.tax,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('1'),
            price: _d('3'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 4, 16),
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows.map((f) => f.amount).toSet(), {-12.0, -3.0});
    });

    test('zero-notional tx is dropped (no NPV term)', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'z',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: Decimal.zero,
            price: Decimal.zero,
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 4, 15),
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows, isEmpty);
    });

    test('non-asset tx (assetId == null) yields no position flow', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'd',
            type: TransactionType.deposit,
            accountId: 'a',
            assetId: null,
            quantity: _d('1'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 4, 15),
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows, isEmpty);
    });
  });

  group('CashFlowExtractor — account scope (exclusion matrix)', () {
    test('every internal type returns null at account scope', () {
      // One transaction per excluded TransactionType — extractor should
      // return zero account-scope flows.
      final flows = _extractor().extract(
        transactions: [
          for (final type in [
            TransactionType.buy,
            TransactionType.sell,
            TransactionType.dividend,
            TransactionType.interest,
            TransactionType.reinvest,
            TransactionType.fee,
            TransactionType.tax,
            TransactionType.valuationAdjust,
            TransactionType.split,
            TransactionType.liabilityPayment,
          ])
            _tx(
              id: 'tx-${type.name}',
              type: type,
              accountId: 'a',
              assetId: 'AAPL',
              quantity: _d('1'),
              price: _d('100'),
              currency: 'USD',
              tradeDate: DateTime.utc(2026, 1, 5),
            ),
        ],
        scope: CashFlowScope.account,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows, isEmpty);
    });

    test('transferIn / transferOut produce signed flows', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'in',
            type: TransactionType.transferIn,
            accountId: 'a',
            assetId: null,
            quantity: _d('1'),
            price: _d('300'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 1),
          ),
          _tx(
            id: 'out',
            type: TransactionType.transferOut,
            accountId: 'a',
            assetId: null,
            quantity: _d('1'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 6, 1),
          ),
        ],
        scope: CashFlowScope.account,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows.map((f) => f.amount).toSet(), {-300.0, 100.0});
    });

    test('zero-notional account flow is dropped', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'd',
            type: TransactionType.deposit,
            accountId: 'a',
            assetId: null,
            quantity: Decimal.zero,
            price: Decimal.zero,
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 4, 15),
          ),
        ],
        scope: CashFlowScope.account,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows, isEmpty);
    });

    test('account-id filter narrows to a subset', () {
      final flows = _extractor().extract(
        transactions: [
          _tx(
            id: 'a',
            type: TransactionType.deposit,
            accountId: 'A',
            assetId: null,
            quantity: _d('1'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 4, 15),
          ),
          _tx(
            id: 'b',
            type: TransactionType.deposit,
            accountId: 'B',
            assetId: null,
            quantity: _d('1'),
            price: _d('200'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 4, 16),
          ),
        ],
        scope: CashFlowScope.account,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
        filter: const CashFlowFilter(accountIds: {'A'}),
      );
      expect(flows.single.amount, -100.0);
    });
  });

  group('CashFlowExtractor — multi-currency unification', () {
    test('CNY / HKD trades convert to USD at trade-date FX', () {
      final extractor = _extractor(
        rates: [
          // 1 CNY = 0.14 USD on the buy date.
          FxRate(
            base: 'CNY',
            quote: 'USD',
            date: DateTime.utc(2026, 1, 5),
            rate: _d('0.14'),
            source: 'fixture',
          ),
          // 1 HKD = 0.13 USD on the dividend date.
          FxRate(
            base: 'HKD',
            quote: 'USD',
            date: DateTime.utc(2026, 6, 15),
            rate: _d('0.13'),
            source: 'fixture',
          ),
        ],
      );
      final flows = extractor.extract(
        transactions: [
          _tx(
            id: 'cny-buy',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: '600519',
            quantity: _d('100'),
            price: _d('1700'), // 1700 CNY/share, total 170,000 CNY
            currency: 'CNY',
            tradeDate: DateTime.utc(2026, 1, 5),
          ),
          _tx(
            id: 'hkd-div',
            type: TransactionType.dividend,
            accountId: 'a',
            assetId: '0700.HK',
            quantity: _d('500'),
            price: _d('2.40'), // 2.40 HKD/share, gross 1200 HKD
            currency: 'HKD',
            tradeDate: DateTime.utc(2026, 6, 15),
          ),
        ],
        scope: CashFlowScope.position,
        range: DateRange(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(flows, hasLength(2));
      // 170,000 CNY * 0.14 = 23,800 USD outflow.
      expect(flows.firstWhere((f) => f.amount < 0).amount, -23800.0);
      // 1,200 HKD * 0.13 = 156 USD inflow.
      expect(flows.firstWhere((f) => f.amount > 0).amount, 156.0);
    });
  });
}
