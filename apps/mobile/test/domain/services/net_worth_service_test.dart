import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/domain/transaction.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/asset_price_source.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/services/liability_balance_source.dart';
import 'package:naviwealth/domain/services/net_worth_service.dart';
import 'package:naviwealth/domain/values/money.dart';

Decimal d(String s) => Decimal.parse(s);

DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: day(2026, 1, 1),
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);

Transaction tx({
  String id = 'tx',
  String accountId = 'acct-1',
  String? assetId,
  required TransactionType type,
  String quantity = '1',
  String price = '1',
  String currency = 'USD',
  required DateTime tradeDate,
  String? fee,
  String? tax,
}) {
  return Transaction(
    id: id,
    accountId: accountId,
    assetId: assetId,
    type: type,
    quantity: d(quantity),
    price: d(price),
    currency: currency,
    tradeDate: tradeDate,
    fee: fee == null ? null : d(fee),
    tax: tax == null ? null : d(tax),
    sync: _meta(),
  );
}

AssetPriceObservation price({
  required String assetId,
  required String price,
  String currency = 'USD',
  required DateTime date,
}) =>
    AssetPriceObservation(
      assetId: assetId,
      price: d(price),
      currency: currency,
      date: date,
    );

FxRate fx({
  String base = 'USD',
  String quote = 'CNY',
  required DateTime date,
  required String rate,
}) =>
    FxRate(
      base: base,
      quote: quote,
      date: date,
      rate: d(rate),
      source: 'test',
    );

NetWorthService _service({
  Iterable<AssetPriceObservation> prices = const [],
  Iterable<LiabilitySnapshot> liabilities = const [],
  Iterable<FxRate> fxRates = const [],
  NetWorthCache? cache,
}) {
  return NetWorthService(
    priceSource: InMemoryAssetPriceSource(prices),
    liabilitySource: AmortizationLiabilitySource(liabilities),
    converter: FxRateCurrencyConverter(InMemoryFxRateLookup(fxRates)),
    cache: cache,
  );
}

void main() {
  group('NetWorthService — empty / boundary', () {
    test('no transactions yields zero-net-worth samples for every day', () {
      final svc = _service();
      final series = svc.timeSeries(
        transactions: const [],
        from: day(2026, 4, 1),
        to: day(2026, 4, 5),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      expect(series.samples.length, 5);
      expect(series.samples.every((s) => s.netWorth == Money.zero('USD')), isTrue);
      expect(series.cashFlows, isEmpty);
    });

    test('to before from is rejected', () {
      final svc = _service();
      expect(
        () => svc.timeSeries(
          transactions: const [],
          from: day(2026, 4, 5),
          to: day(2026, 4, 1),
          granularity: NetWorthGranularity.day,
          baseCurrency: 'USD',
        ),
        throwsArgumentError,
      );
    });

    test('to == from yields a single sample', () {
      final svc = _service();
      final series = svc.timeSeries(
        transactions: const [],
        from: day(2026, 4, 1),
        to: day(2026, 4, 1),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      expect(series.samples.length, 1);
      expect(series.samples.single.asOf, day(2026, 4, 1));
    });
  });

  group('NetWorthService — single-currency holdings', () {
    test('buy then hold values position at each sample\'s price', () {
      final svc = _service(
        prices: [
          price(assetId: 'AAPL', price: '150', date: day(2026, 4, 1)),
          price(assetId: 'AAPL', price: '160', date: day(2026, 4, 2)),
          price(assetId: 'AAPL', price: '170', date: day(2026, 4, 3)),
        ],
      );
      // Deposit $20k on Apr 1, buy 100 AAPL @ $150 same day.
      final series = svc.timeSeries(
        transactions: [
          tx(
            id: 'd1',
            type: TransactionType.deposit,
            quantity: '20000',
            tradeDate: day(2026, 4, 1),
          ),
          tx(
            id: 'b1',
            assetId: 'AAPL',
            type: TransactionType.buy,
            quantity: '100',
            price: '150',
            tradeDate: day(2026, 4, 1),
          ),
        ],
        from: day(2026, 4, 1),
        to: day(2026, 4, 3),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      // Day 1: 100 * 150 = 15000 + 5000 cash = 20000
      // Day 2: 100 * 160 = 16000 + 5000 cash = 21000
      // Day 3: 100 * 170 = 17000 + 5000 cash = 22000
      expect(series.samples[0].assets, Money.parse('20000', 'USD'));
      expect(series.samples[1].assets, Money.parse('21000', 'USD'));
      expect(series.samples[2].assets, Money.parse('22000', 'USD'));
      expect(series.samples.every((s) => s.liabilities.isZero), isTrue);
      expect(series.samples[0].netWorth, Money.parse('20000', 'USD'));
      expect(series.samples[2].netWorth, Money.parse('22000', 'USD'));
    });

    test('sell realizes cash and removes position', () {
      final svc = _service(
        prices: [
          price(assetId: 'AAPL', price: '150', date: day(2026, 4, 1)),
          price(assetId: 'AAPL', price: '180', date: day(2026, 4, 5)),
        ],
      );
      final series = svc.timeSeries(
        transactions: [
          tx(
            id: 'd',
            type: TransactionType.deposit,
            quantity: '20000',
            tradeDate: day(2026, 4, 1),
          ),
          tx(
            id: 'b',
            assetId: 'AAPL',
            type: TransactionType.buy,
            quantity: '100',
            price: '150',
            tradeDate: day(2026, 4, 1),
          ),
          // Sell all 100 shares on Apr 5 @ $180.
          tx(
            id: 's',
            assetId: 'AAPL',
            type: TransactionType.sell,
            quantity: '100',
            price: '180',
            tradeDate: day(2026, 4, 5),
          ),
        ],
        from: day(2026, 4, 1),
        to: day(2026, 4, 5),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      // Apr 1: cash 5000 + position 15000 = 20000
      // Apr 5: cash 5000 + 18000 sale proceeds = 23000, position closed
      expect(series.samples.first.netWorth, Money.parse('20000', 'USD'));
      expect(series.samples.last.netWorth, Money.parse('23000', 'USD'));
    });

    test('buy fees reduce cash but not the position market value', () {
      final svc = _service(
        prices: [
          price(assetId: 'AAPL', price: '150', date: day(2026, 4, 1)),
        ],
      );
      final series = svc.timeSeries(
        transactions: [
          tx(
            id: 'd',
            type: TransactionType.deposit,
            quantity: '20000',
            tradeDate: day(2026, 4, 1),
          ),
          tx(
            id: 'b',
            assetId: 'AAPL',
            type: TransactionType.buy,
            quantity: '100',
            price: '150',
            fee: '10',
            tradeDate: day(2026, 4, 1),
          ),
        ],
        from: day(2026, 4, 1),
        to: day(2026, 4, 1),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      // 20000 - 15000 - 10 fee = 4990 cash; position = 15000; total = 19990.
      expect(series.samples.single.assets, Money.parse('19990', 'USD'));
    });

    test('reinvest grows position without moving cash', () {
      final svc = _service(
        prices: [
          price(assetId: 'AAPL', price: '150', date: day(2026, 4, 1)),
          price(assetId: 'AAPL', price: '150', date: day(2026, 4, 2)),
        ],
      );
      final series = svc.timeSeries(
        transactions: [
          tx(
            id: 'd',
            type: TransactionType.deposit,
            quantity: '20000',
            tradeDate: day(2026, 4, 1),
          ),
          tx(
            id: 'b',
            assetId: 'AAPL',
            type: TransactionType.buy,
            quantity: '100',
            price: '150',
            tradeDate: day(2026, 4, 1),
          ),
          tx(
            id: 'r',
            assetId: 'AAPL',
            type: TransactionType.reinvest,
            quantity: '5',
            price: '150',
            tradeDate: day(2026, 4, 2),
          ),
        ],
        from: day(2026, 4, 1),
        to: day(2026, 4, 2),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      // Apr 2: cash 5000 + 105 shares * 150 = 5000 + 15750 = 20750
      expect(series.samples.last.assets, Money.parse('20750', 'USD'));
    });

    test('split adds shares (already split-adjusted in the price book)', () {
      final svc = _service(
        prices: [
          price(assetId: 'AAPL', price: '150', date: day(2026, 4, 1)),
          // Post-split on Apr 2 the price feed shows the adjusted price.
          price(assetId: 'AAPL', price: '75', date: day(2026, 4, 2)),
        ],
      );
      final series = svc.timeSeries(
        transactions: [
          tx(
            id: 'd',
            type: TransactionType.deposit,
            quantity: '15000',
            tradeDate: day(2026, 4, 1),
          ),
          tx(
            id: 'b',
            assetId: 'AAPL',
            type: TransactionType.buy,
            quantity: '100',
            price: '150',
            tradeDate: day(2026, 4, 1),
          ),
          // 2-for-1 split on Apr 2: +100 shares booked.
          tx(
            id: 'sp',
            assetId: 'AAPL',
            type: TransactionType.split,
            quantity: '100',
            price: '0',
            tradeDate: day(2026, 4, 2),
          ),
        ],
        from: day(2026, 4, 1),
        to: day(2026, 4, 2),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      // Apr 1: 15000 (100 * 150)
      // Apr 2: 200 shares * 75 = 15000 — total preserved.
      expect(series.samples.first.assets, Money.parse('15000', 'USD'));
      expect(series.samples.last.assets, Money.parse('15000', 'USD'));
    });
  });

  group('NetWorthService — multi-currency conversion', () {
    test('foreign-currency holdings convert at each sample\'s rate', () {
      final svc = _service(
        prices: [
          // 700.HK quoted in HKD.
          price(
            assetId: '700.HK',
            currency: 'HKD',
            price: '400',
            date: day(2026, 4, 1),
          ),
          price(
            assetId: '700.HK',
            currency: 'HKD',
            price: '400',
            date: day(2026, 4, 2),
          ),
        ],
        fxRates: [
          // 1 HKD = 0.13 USD on Apr 1; the rate strengthens to 0.14 on Apr 2.
          fx(base: 'HKD', quote: 'USD', date: day(2026, 4, 1), rate: '0.13'),
          fx(base: 'HKD', quote: 'USD', date: day(2026, 4, 2), rate: '0.14'),
        ],
      );
      final series = svc.timeSeries(
        transactions: [
          // 100 shares * 400 HKD = 40,000 HKD position (no cash leg modeled
          // — the buy is funded externally so we omit the deposit and the
          // buy doesn't go negative because we're testing the FX path).
          tx(
            id: 'b',
            accountId: 'hk-acct',
            assetId: '700.HK',
            type: TransactionType.buy,
            quantity: '100',
            price: '400',
            currency: 'HKD',
            tradeDate: day(2026, 4, 1),
          ),
          // Offset the buy's cash leg with a same-day HKD deposit.
          tx(
            id: 'd',
            accountId: 'hk-acct',
            type: TransactionType.deposit,
            quantity: '40000',
            currency: 'HKD',
            tradeDate: day(2026, 4, 1),
          ),
        ],
        from: day(2026, 4, 1),
        to: day(2026, 4, 2),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      // Apr 1: 40,000 HKD * 0.13 = 5,200 USD
      // Apr 2: 40,000 HKD * 0.14 = 5,600 USD (price flat, FX moved)
      expect(series.samples[0].assets, Money.parse('5200.00', 'USD'));
      expect(series.samples[1].assets, Money.parse('5600.00', 'USD'));
    });
  });

  group('NetWorthService — liabilities', () {
    test('liability outstanding is subtracted from assets', () {
      final svc = _service(
        liabilities: [
          LiabilitySnapshot(
            id: 'mortgage',
            currency: 'USD',
            initialPrincipal: d('500000'),
            startDate: day(2026, 1, 1),
            schedule: [
              AmortizationPoint(
                dueDate: day(2026, 1, 31),
                remainingBalance: d('495000'),
              ),
              AmortizationPoint(
                dueDate: day(2026, 2, 28),
                remainingBalance: d('490000'),
              ),
            ],
          ),
        ],
      );
      final series = svc.timeSeries(
        transactions: [
          tx(
            id: 'd',
            type: TransactionType.deposit,
            quantity: '600000',
            tradeDate: day(2026, 1, 1),
          ),
        ],
        from: day(2026, 1, 1),
        to: day(2026, 3, 1),
        granularity: NetWorthGranularity.month,
        baseCurrency: 'USD',
      );
      // The liability schedule kicks in at end of January.
      // Jan 1: assets 600k, liability initial 500k → net 100k.
      // Jan 31: assets 600k, liability 495k → net 105k.
      // Feb 28: assets 600k, liability 490k → net 110k.
      // Mar 1 (sample tail): liability still 490k → net 110k.
      expect(
        series.samples.map((s) => s.netWorth).toList(),
        [
          Money.parse('100000', 'USD'),
          Money.parse('105000', 'USD'),
          Money.parse('110000', 'USD'),
          Money.parse('110000', 'USD'),
        ],
      );
    });

    test('liabilityPayment moves cash out without an external cash flow', () {
      final svc = _service(
        liabilities: [
          LiabilitySnapshot(
            id: 'mortgage',
            currency: 'USD',
            initialPrincipal: d('100000'),
            startDate: day(2026, 1, 1),
            schedule: [
              AmortizationPoint(
                dueDate: day(2026, 1, 31),
                remainingBalance: d('99000'),
              ),
            ],
          ),
        ],
      );
      final series = svc.timeSeries(
        transactions: [
          tx(
            id: 'd',
            type: TransactionType.deposit,
            quantity: '120000',
            tradeDate: day(2026, 1, 1),
          ),
          // FIR-47 shape: qty=1, price=monthly payment (1500 = 1000 principal
          // + 500 interest). The principal drop (1000) is already baked into
          // the schedule's remainingBalance for Jan 31.
          tx(
            id: 'pay',
            type: TransactionType.liabilityPayment,
            quantity: '1',
            price: '1500',
            tradeDate: day(2026, 1, 31),
          ),
        ],
        from: day(2026, 1, 1),
        to: day(2026, 1, 31),
        granularity: NetWorthGranularity.month,
        baseCurrency: 'USD',
      );
      // Jan 1: assets 120k, liabilities 100k → net 20k.
      expect(series.samples.first.netWorth, Money.parse('20000', 'USD'));
      // Jan 31: assets 120k - 1500 = 118500, liabilities 99000 → net 19500.
      // The 500 interest is the actual loss in net worth that month.
      expect(series.samples.last.netWorth, Money.parse('19500', 'USD'));
      // liabilityPayment is intra-portfolio — never tagged for XIRR.
      expect(series.cashFlows.length, 1);
      expect(series.cashFlows.single.transactionId, 'd');
    });

    test('liability before its startDate is excluded', () {
      final svc = _service(
        liabilities: [
          LiabilitySnapshot(
            id: 'future-loan',
            currency: 'USD',
            initialPrincipal: d('100000'),
            startDate: day(2026, 6, 1),
            schedule: const [],
          ),
        ],
      );
      final series = svc.timeSeries(
        transactions: const [],
        from: day(2026, 1, 1),
        to: day(2026, 3, 1),
        granularity: NetWorthGranularity.month,
        baseCurrency: 'USD',
      );
      expect(series.samples.every((s) => s.liabilities.isZero), isTrue);
    });
  });

  group('NetWorthService — cash flows for XIRR', () {
    test('deposit / withdraw are tagged; buy / dividend are not', () {
      final svc = _service(
        prices: [
          price(assetId: 'AAPL', price: '150', date: day(2026, 4, 1)),
        ],
      );
      final series = svc.timeSeries(
        transactions: [
          tx(
            id: 'd1',
            type: TransactionType.deposit,
            quantity: '10000',
            tradeDate: day(2026, 4, 1),
          ),
          tx(
            id: 'b1',
            assetId: 'AAPL',
            type: TransactionType.buy,
            quantity: '50',
            price: '150',
            tradeDate: day(2026, 4, 2),
          ),
          tx(
            id: 'div',
            assetId: 'AAPL',
            type: TransactionType.dividend,
            quantity: '50',
            price: '1',
            tradeDate: day(2026, 4, 3),
          ),
          tx(
            id: 'w1',
            type: TransactionType.withdraw,
            quantity: '500',
            tradeDate: day(2026, 4, 4),
          ),
        ],
        from: day(2026, 4, 1),
        to: day(2026, 4, 4),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      expect(series.cashFlows.length, 2);
      expect(series.cashFlows[0].transactionId, 'd1');
      expect(series.cashFlows[0].amount, Money.parse('10000', 'USD'));
      expect(series.cashFlows[0].type, TransactionType.deposit);
      expect(series.cashFlows[1].transactionId, 'w1');
      expect(series.cashFlows[1].amount, Money.parse('-500', 'USD'));
      expect(series.cashFlows[1].type, TransactionType.withdraw);
    });

    test('per-bucket netCashFlow is converted to base currency', () {
      final svc = _service(
        fxRates: [
          fx(date: day(2026, 4, 1), rate: '7.0'),
          fx(date: day(2026, 4, 2), rate: '7.2'),
        ],
      );
      // Deposit 100 USD on Apr 1 (FX 7.0 → 700 CNY) and 100 USD on Apr 2
      // (FX 7.2 → 720 CNY). With weekly granularity, both fall into the
      // first sample's bucket.
      final series = svc.timeSeries(
        transactions: [
          tx(
            id: 'd1',
            type: TransactionType.deposit,
            quantity: '100',
            tradeDate: day(2026, 4, 1),
          ),
          tx(
            id: 'd2',
            type: TransactionType.deposit,
            quantity: '100',
            tradeDate: day(2026, 4, 2),
          ),
        ],
        from: day(2026, 4, 1),
        to: day(2026, 4, 2),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'CNY',
      );
      expect(series.samples[0].netCashFlow, Money.parse('700.0', 'CNY'));
      expect(series.samples[1].netCashFlow, Money.parse('720.0', 'CNY'));
    });
  });

  group('NetWorthService — caching', () {
    test('repeated identical query is served from cache', () {
      final cache = NetWorthCache();
      final svc = _service(
        prices: [
          price(assetId: 'AAPL', price: '150', date: day(2026, 4, 1)),
        ],
        cache: cache,
      );
      final txs = [
        tx(
          id: 'd',
          type: TransactionType.deposit,
          quantity: '20000',
          tradeDate: day(2026, 4, 1),
        ),
      ];
      final first = svc.timeSeries(
        transactions: txs,
        from: day(2026, 4, 1),
        to: day(2026, 4, 1),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      expect(cache.size, 1);
      final second = svc.timeSeries(
        transactions: txs,
        from: day(2026, 4, 1),
        to: day(2026, 4, 1),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      // Identity equality — cached call returns the same instance.
      expect(identical(first, second), isTrue);
    });

    test('cache misses when transaction set grows', () {
      final cache = NetWorthCache();
      final svc = _service(cache: cache);
      final txs1 = [
        tx(
          id: 'd1',
          type: TransactionType.deposit,
          quantity: '100',
          tradeDate: day(2026, 4, 1),
        ),
      ];
      final first = svc.timeSeries(
        transactions: txs1,
        from: day(2026, 4, 1),
        to: day(2026, 4, 2),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );

      final txs2 = [
        ...txs1,
        tx(
          id: 'd2',
          type: TransactionType.deposit,
          quantity: '50',
          tradeDate: day(2026, 4, 2),
        ),
      ];
      final second = svc.timeSeries(
        transactions: txs2,
        from: day(2026, 4, 1),
        to: day(2026, 4, 2),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );

      expect(identical(first, second), isFalse);
      expect(first.samples.last.assets, Money.parse('100', 'USD'));
      expect(second.samples.last.assets, Money.parse('150', 'USD'));
      expect(cache.size, 2);
    });

    test('invalidate clears the cache', () {
      final svc = _service();
      svc.timeSeries(
        transactions: const [],
        from: day(2026, 4, 1),
        to: day(2026, 4, 1),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      svc.invalidate();
      // After invalidation a follow-up call recomputes — assert a fresh
      // instance is produced even with the same args.
      final first = svc.timeSeries(
        transactions: const [],
        from: day(2026, 4, 1),
        to: day(2026, 4, 1),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      svc.invalidate();
      final second = svc.timeSeries(
        transactions: const [],
        from: day(2026, 4, 1),
        to: day(2026, 4, 1),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      expect(identical(first, second), isFalse);
    });
  });

  group('NetWorthService — granularity', () {
    test('week granularity steps every 7 days and forces final sample on `to`',
        () {
      final svc = _service();
      final series = svc.timeSeries(
        transactions: const [],
        from: day(2026, 1, 1),
        to: day(2026, 1, 20),
        granularity: NetWorthGranularity.week,
        baseCurrency: 'USD',
      );
      expect(
        series.samples.map((s) => s.asOf).toList(),
        [
          day(2026, 1, 1),
          day(2026, 1, 8),
          day(2026, 1, 15),
          day(2026, 1, 20), // forced tail
        ],
      );
    });

    test('month granularity anchors on month-ends and brackets on `from`/`to`',
        () {
      final svc = _service();
      final series = svc.timeSeries(
        transactions: const [],
        from: day(2026, 1, 15),
        to: day(2026, 4, 10),
        granularity: NetWorthGranularity.month,
        baseCurrency: 'USD',
      );
      expect(
        series.samples.map((s) => s.asOf).toList(),
        [
          day(2026, 1, 15),
          day(2026, 1, 31),
          day(2026, 2, 28),
          day(2026, 3, 31),
          day(2026, 4, 10),
        ],
      );
    });

    test('day granularity 5-year horizon (1827 days) builds without error', () {
      final svc = _service();
      final series = svc.timeSeries(
        transactions: const [],
        from: day(2021, 4, 28),
        to: day(2026, 4, 28),
        granularity: NetWorthGranularity.day,
        baseCurrency: 'USD',
      );
      expect(series.samples.length, 1827); // 5 years incl. one leap day.
    });
  });

  group('InMemoryAssetPriceSource', () {
    test('returns null before any observation', () {
      final src = InMemoryAssetPriceSource([
        price(assetId: 'A', price: '10', date: day(2026, 4, 5)),
      ]);
      expect(src.priceOn('A', day(2026, 4, 1)), isNull);
      expect(src.priceOn('UNKNOWN', day(2026, 4, 5)), isNull);
    });

    test('backfills to nearest earlier observation', () {
      final src = InMemoryAssetPriceSource([
        price(assetId: 'A', price: '10', date: day(2026, 4, 1)),
        price(assetId: 'A', price: '12', date: day(2026, 4, 5)),
      ]);
      // Holiday gap on 4/3: should pick 10 (the 4/1 obs).
      expect(src.priceOn('A', day(2026, 4, 3)), d('10'));
      expect(src.priceOn('A', day(2026, 4, 5)), d('12'));
      expect(src.priceOn('A', day(2026, 4, 10)), d('12'));
    });

    test('rejects mixed currencies for the same asset', () {
      expect(
        () => InMemoryAssetPriceSource([
          price(assetId: 'A', price: '10', currency: 'USD', date: day(2026, 4, 1)),
          price(assetId: 'A', price: '70', currency: 'CNY', date: day(2026, 4, 2)),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('AmortizationLiabilitySource', () {
    test('returns initial principal before any schedule entry', () {
      final src = AmortizationLiabilitySource([
        LiabilitySnapshot(
          id: 'L',
          currency: 'USD',
          initialPrincipal: d('1000'),
          startDate: day(2026, 1, 1),
          schedule: [
            AmortizationPoint(
              dueDate: day(2026, 2, 1),
              remainingBalance: d('900'),
            ),
          ],
        ),
      ]);
      expect(src.balancesOn(day(2026, 1, 15)).single.outstanding,
          Money.parse('1000', 'USD'));
      expect(src.balancesOn(day(2026, 2, 15)).single.outstanding,
          Money.parse('900', 'USD'));
    });

    test('omits liabilities paid down to zero', () {
      final src = AmortizationLiabilitySource([
        LiabilitySnapshot(
          id: 'L',
          currency: 'USD',
          initialPrincipal: d('1000'),
          startDate: day(2026, 1, 1),
          schedule: [
            AmortizationPoint(
              dueDate: day(2026, 6, 1),
              remainingBalance: d('0'),
            ),
          ],
        ),
      ]);
      expect(src.balancesOn(day(2026, 7, 1)), isEmpty);
    });
  });
}
