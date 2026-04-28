import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/investment/domain/cost_basis/fifo_strategy.dart';
import 'package:naviwealth/features/investment/domain/cost_basis_engine.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/default_trade_entry_service.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_entry_errors.dart';

import '_fakes.dart';

Decimal d(String s) => Decimal.parse(s);

class _SequentialIds {
  _SequentialIds([this.prefix = 'id']);
  final String prefix;
  int _n = 0;
  String next() => '$prefix-${++_n}';
}

DefaultTradeEntryService buildService({
  FakeMarketDataService? market,
  CurrencyConverter? fx,
  CostBasisEngine? engine,
  bool permissiveSells = false,
  String Function()? idGenerator,
  CountingHlcStamper? stamper,
}) {
  final m = market ?? FakeMarketDataService();
  final f = fx ?? FxRateCurrencyConverter(InMemoryFxRateLookup(const []));
  final ids = idGenerator ?? _SequentialIds('tx').next;
  return DefaultTradeEntryService(
    market: m,
    fx: f,
    stampHlc: (stamper ?? CountingHlcStamper()).call,
    ownerUserId: 'user-1',
    deviceId: 'device-1',
    engine: engine ??
        CostBasisEngine(
          strategy: const FifoStrategy(),
          idGenerator: _SequentialIds('lot').next,
        ),
    idGenerator: ids,
    now: () => DateTime.utc(2026, 4, 28, 12),
    permissiveSells: permissiveSells,
  );
}

void main() {
  group('Buy with user-supplied price', () {
    test('opens a fresh lot, embeds sync meta on the transaction', () async {
      final svc = buildService();
      final plan = await svc.buildPlan(
        TradeDraft(
          type: TransactionType.buy,
          asset: asset(symbol: 'AAPL'),
          accountId: 'acct-1',
          quantity: d('10'),
          price: d('150'),
          fee: d('1'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 1, 5),
        ),
        openLots: const [],
      );

      expect(plan.transaction.id, 'tx-1');
      expect(plan.transaction.type, TransactionType.buy);
      expect(plan.transaction.price, d('150'));
      expect(plan.transaction.sync.ownerUserId, 'user-1');
      expect(plan.transaction.sync.updatedByDevice, 'device-1');
      expect(plan.transaction.sync.hlc.wallMillis, 1);
      expect(plan.pricing.wasBackfilled, isFalse);

      final lot = plan.createdLot!;
      expect(lot.openingTransactionId, 'tx-1');
      // (10 * 150 + 1) / 10 = 150.1
      expect(lot.costPerUnit, d('150.1'));
      expect(lot.remainingQuantity, d('10'));
    });
  });

  group('Buy with price backfill', () {
    test('uses the trade-day close from market data and tags provenance',
        () async {
      final svc = buildService(
        market: FakeMarketDataService(
          historical: {
            'AAPL': [
              bar('AAPL', DateTime.utc(2026, 1, 4), '149'),
              bar('AAPL', DateTime.utc(2026, 1, 5), '152'),
              bar('AAPL', DateTime.utc(2026, 1, 6), '155'),
            ],
          },
          source: 'fake-yfin',
        ),
      );
      final plan = await svc.buildPlan(
        TradeDraft(
          type: TransactionType.buy,
          asset: asset(symbol: 'AAPL'),
          accountId: 'acct-1',
          quantity: d('5'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 1, 5),
        ),
        openLots: const [],
      );

      expect(plan.transaction.price, d('152'));
      expect(plan.pricing.wasBackfilled, isTrue);
      expect(plan.pricing.marketSource, 'fake-yfin');
      expect(plan.pricing.barAsOf, DateTime.utc(2026, 1, 5));
      expect(plan.pricing.fxConverted, isFalse);
    });

    test('falls back to the most recent prior bar when trade date is closed',
        () async {
      // Trade on a Saturday — pick the Friday close.
      final svc = buildService(
        market: FakeMarketDataService(
          historical: {
            'AAPL': [
              bar('AAPL', DateTime.utc(2026, 1, 2), '100'), // Friday
            ],
          },
        ),
      );
      final plan = await svc.buildPlan(
        TradeDraft(
          type: TransactionType.buy,
          asset: asset(symbol: 'AAPL'),
          accountId: 'acct-1',
          quantity: d('1'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 1, 3), // Saturday
        ),
        openLots: const [],
      );

      expect(plan.transaction.price, d('100'));
      expect(plan.pricing.barAsOf, DateTime.utc(2026, 1, 2));
    });

    test('throws priceUnavailable when the provider returns no bars',
        () async {
      final svc = buildService();
      expect(
        () => svc.buildPlan(
          TradeDraft(
            type: TransactionType.buy,
            asset: asset(symbol: 'NOPE'),
            accountId: 'acct-1',
            quantity: d('1'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 5),
          ),
          openLots: const [],
        ),
        throwsA(
          isA<TradeEntryException>().having(
            (e) => e.code,
            'code',
            TradeEntryErrorCode.priceUnavailable,
          ),
        ),
      );
    });
  });

  group('Buy with FX conversion', () {
    test(
        'converts the asset-currency close into the trade currency on the '
        'trade date', () async {
      // Asset trades in HKD; user records the trade in USD. Bar close = 80
      // HKD; rate HKD→USD = 0.128 → expected 10.24 USD.
      final svc = buildService(
        market: FakeMarketDataService(
          historical: {
            '0700.HK': [
              bar('0700.HK', DateTime.utc(2026, 1, 5), '80'),
            ],
          },
        ),
        fx: fxConverter(
          base: 'HKD',
          quote: 'USD',
          rate: '0.128',
          on: DateTime.utc(2026, 1, 5),
        ),
      );
      final plan = await svc.buildPlan(
        TradeDraft(
          type: TransactionType.buy,
          asset: asset(
            id: 'tencent',
            type: AssetType.stock,
            symbol: '0700.HK',
            currency: 'HKD',
          ),
          accountId: 'acct-1',
          quantity: d('100'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 1, 5),
        ),
        openLots: const [],
      );

      expect(plan.transaction.price, d('10.24'));
      expect(plan.pricing.fxConverted, isTrue);
      expect(plan.pricing.fxFromCurrency, 'HKD');
      expect(plan.pricing.fxRate, d('0.128'));
    });

    test('throws currencyMismatch when no FX rate is registered', () async {
      final svc = buildService(
        market: FakeMarketDataService(
          historical: {
            '0700.HK': [bar('0700.HK', DateTime.utc(2026, 1, 5), '80')],
          },
        ),
        fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
      );
      expect(
        () => svc.buildPlan(
          TradeDraft(
            type: TransactionType.buy,
            asset: asset(symbol: '0700.HK', currency: 'HKD'),
            accountId: 'acct-1',
            quantity: d('1'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 5),
          ),
          openLots: const [],
        ),
        throwsA(
          isA<TradeEntryException>().having(
            (e) => e.code,
            'code',
            TradeEntryErrorCode.currencyMismatch,
          ),
        ),
      );
    });
  });

  group('Sell', () {
    test('FIFO consumes oldest lot first and emits realized PnL', () async {
      final svc = buildService();
      final lots = [
        Lot(
          id: 'lot-old',
          openingTransactionId: 'tx-old',
          accountId: 'acct-1',
          assetId: 'asset-1',
          currency: 'USD',
          originalQuantity: d('40'),
          remainingQuantity: d('40'),
          costPerUnit: d('10'),
          openedAt: DateTime.utc(2026, 1, 1),
        ),
        Lot(
          id: 'lot-new',
          openingTransactionId: 'tx-new',
          accountId: 'acct-1',
          assetId: 'asset-1',
          currency: 'USD',
          originalQuantity: d('60'),
          remainingQuantity: d('60'),
          costPerUnit: d('15'),
          openedAt: DateTime.utc(2026, 1, 5),
        ),
      ];
      final plan = await svc.buildPlan(
        TradeDraft(
          type: TransactionType.sell,
          asset: asset(),
          accountId: 'acct-1',
          quantity: d('50'),
          price: d('20'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
        openLots: lots,
      );

      expect(plan.realizedPnL, hasLength(2));
      expect(plan.unfulfilledQuantity, Decimal.zero);

      // Only the changed lots come back — the old one closed, the new one
      // partially consumed.
      expect(plan.updatedLots, hasLength(2));
      final closed = plan.updatedLots.firstWhere((l) => l.id == 'lot-old');
      final partial = plan.updatedLots.firstWhere((l) => l.id == 'lot-new');
      expect(closed.remainingQuantity, Decimal.zero);
      expect(partial.remainingQuantity, d('50'));
    });

    test('rejects sells that exceed open lots in strict mode', () async {
      final svc = buildService();
      expect(
        () => svc.buildPlan(
          TradeDraft(
            type: TransactionType.sell,
            asset: asset(),
            accountId: 'acct-1',
            quantity: d('10'),
            price: d('20'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 2, 1),
          ),
          openLots: const [],
        ),
        throwsA(
          isA<TradeEntryException>().having(
            (e) => e.code,
            'code',
            TradeEntryErrorCode.insufficientHoldings,
          ),
        ),
      );
    });

    test('reports unfulfilled quantity when permissive mode is on', () async {
      final svc = buildService(permissiveSells: true);
      final lots = [
        Lot(
          id: 'lot-1',
          openingTransactionId: 'tx-1',
          accountId: 'acct-1',
          assetId: 'asset-1',
          currency: 'USD',
          originalQuantity: d('5'),
          remainingQuantity: d('5'),
          costPerUnit: d('10'),
          openedAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      final plan = await svc.buildPlan(
        TradeDraft(
          type: TransactionType.sell,
          asset: asset(),
          accountId: 'acct-1',
          quantity: d('20'),
          price: d('25'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
        openLots: lots,
      );

      expect(plan.unfulfilledQuantity, d('15'));
      expect(plan.realizedPnL, hasLength(1));
    });
  });

  group('Transfers', () {
    test(
        'transferIn behaves like a buy for cost-basis purposes and requires '
        'a counter account', () async {
      final svc = buildService();
      final plan = await svc.buildPlan(
        TradeDraft(
          type: TransactionType.transferIn,
          asset: asset(),
          accountId: 'dst-acct',
          counterAccountId: 'src-acct',
          quantity: d('5'),
          price: d('100'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
        openLots: const [],
      );

      expect(plan.createdLot, isNotNull);
      expect(plan.createdLot!.accountId, 'dst-acct');
      expect(plan.transaction.counterAccountId, 'src-acct');
    });

    test('transferOut consumes lots but emits no realized PnL', () async {
      final svc = buildService();
      final lots = [
        Lot(
          id: 'lot-1',
          openingTransactionId: 'tx-1',
          accountId: 'src-acct',
          assetId: 'asset-1',
          currency: 'USD',
          originalQuantity: d('10'),
          remainingQuantity: d('10'),
          costPerUnit: d('100'),
          openedAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      final plan = await svc.buildPlan(
        TradeDraft(
          type: TransactionType.transferOut,
          asset: asset(),
          accountId: 'src-acct',
          counterAccountId: 'dst-acct',
          quantity: d('3'),
          price: d('110'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
        openLots: lots,
      );

      expect(plan.realizedPnL, isEmpty);
      expect(plan.updatedLots.single.remainingQuantity, d('7'));
    });

    test('transfer without a counter account is rejected', () async {
      final svc = buildService();
      expect(
        () => svc.buildPlan(
          TradeDraft(
            type: TransactionType.transferIn,
            asset: asset(),
            accountId: 'dst',
            quantity: d('1'),
            price: d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 2, 1),
          ),
          openLots: const [],
        ),
        throwsA(
          isA<TradeEntryException>().having(
            (e) => e.code,
            'code',
            TradeEntryErrorCode.transferMissingCounterAccount,
          ),
        ),
      );
    });
  });

  group('Validation', () {
    test('non-positive quantity is rejected', () async {
      final svc = buildService();
      expect(
        () => svc.buildPlan(
          TradeDraft(
            type: TransactionType.buy,
            asset: asset(),
            accountId: 'a',
            quantity: Decimal.zero,
            price: d('1'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 2, 1),
          ),
          openLots: const [],
        ),
        throwsA(
          isA<TradeEntryException>().having(
            (e) => e.code,
            'code',
            TradeEntryErrorCode.quantityNotPositive,
          ),
        ),
      );
    });

    test('negative fee is rejected', () async {
      final svc = buildService();
      expect(
        () => svc.buildPlan(
          TradeDraft(
            type: TransactionType.buy,
            asset: asset(),
            accountId: 'a',
            quantity: d('1'),
            price: d('1'),
            fee: d('-1'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 2, 1),
          ),
          openLots: const [],
        ),
        throwsA(
          isA<TradeEntryException>().having(
            (e) => e.code,
            'code',
            TradeEntryErrorCode.amountNegative,
          ),
        ),
      );
    });

    test('crypto allows up to 18 fractional digits in quantity', () async {
      final svc = buildService();
      final plan = await svc.buildPlan(
        TradeDraft(
          type: TransactionType.buy,
          asset: asset(type: AssetType.crypto, symbol: 'BTC', currency: 'USD'),
          accountId: 'a',
          quantity: d('0.000000000000000001'),
          price: d('60000'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
        openLots: const [],
      );
      expect(plan.transaction.quantity, d('0.000000000000000001'));
    });

    test('stocks beyond 8 fractional digits are rejected', () async {
      final svc = buildService();
      expect(
        () => svc.buildPlan(
          TradeDraft(
            type: TransactionType.buy,
            asset: asset(),
            accountId: 'a',
            quantity: d('0.123456789'), // 9 digits — over the cap of 8
            price: d('1'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 2, 1),
          ),
          openLots: const [],
        ),
        throwsA(
          isA<TradeEntryException>().having(
            (e) => e.code,
            'code',
            TradeEntryErrorCode.quantityScaleExceeded,
          ),
        ),
      );
    });

    test(
        'pure cash flows like deposit / fee / dividend are not handled '
        'by trade entry', () async {
      final svc = buildService();
      expect(
        () => svc.buildPlan(
          TradeDraft(
            type: TransactionType.dividend,
            asset: asset(),
            accountId: 'a',
            quantity: d('1'),
            price: d('1'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 2, 1),
          ),
          openLots: const [],
        ),
        throwsA(
          isA<TradeEntryException>().having(
            (e) => e.code,
            'code',
            TradeEntryErrorCode.fieldRequired,
          ),
        ),
      );
    });
  });

  group('valuationAdjust', () {
    test('records a transaction with no lot impact', () async {
      final svc = buildService();
      final plan = await svc.buildPlan(
        TradeDraft(
          type: TransactionType.valuationAdjust,
          asset: asset(),
          accountId: 'a',
          quantity: Decimal.zero,
          price: d('123.45'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
        openLots: const [],
      );

      expect(plan.createdLot, isNull);
      expect(plan.realizedPnL, isEmpty);
      expect(plan.transaction.price, d('123.45'));
    });
  });

  group('buildDeletePlan', () {
    test('mirrors the transaction id and any lots to release', () {
      final svc = buildService();
      final plan = svc.buildDeletePlan(
        transactionId: 'tx-1',
        createdLotIds: ['lot-1', 'lot-2'],
      );

      expect(plan.transactionId, 'tx-1');
      expect(plan.releaseLotIds, ['lot-1', 'lot-2']);
    });

    test('throws when transactionId is empty', () {
      final svc = buildService();
      expect(
        () => svc.buildDeletePlan(transactionId: '', createdLotIds: const []),
        throwsA(isA<TradeEntryException>()),
      );
    });
  });
}
