import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/liability.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart' as dom;
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset_meta.dart';
import 'package:naviwealth/features/home/domain/dashboard_aggregator.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/liabilities/domain/liability_summary.dart';

Decimal d(String s) => Decimal.parse(s);

DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);

SyncMeta _meta() => SyncMeta(
      ownerUserId: 'u',
      updatedAt: day(2026, 4, 1),
      updatedByDevice: 'test',
      hlc: Hlc.zero('test'),
    );

Asset _manualAsset({
  required String id,
  required AssetType type,
  String currency = 'CNY',
  required String price,
  String name = 'Asset',
}) {
  return Asset(
    id: id,
    type: type,
    symbol: id,
    currency: currency,
    name: name,
    lastPrice: d(price),
    sync: _meta(),
  );
}

PhysicalAsset _physicalAsset({
  required String id,
  required AssetType type,
  String currency = 'CNY',
  required String purchase,
  required String current,
  String name = 'Asset',
}) {
  final meta = PhysicalAssetMeta(
    purchaseDate: day(2024, 1, 1),
    purchasePrice: d(purchase),
  );
  final row = AssetRow(
    id: id,
    ownerUserId: 'u',
    updatedAt: day(2026, 4, 1),
    updatedByDevice: 'test',
    hlc: Hlc.zero('test'),
    type: type,
    symbol: id,
    currency: currency,
    name: name,
    lastPrice: d(current),
    metadataJson: meta.encode(),
  );
  return PhysicalAsset(row: row, meta: meta);
}

Liability _liability({
  required String id,
  required String name,
  required String principal,
  String currency = 'CNY',
  LiabilityType type = LiabilityType.mortgage,
}) {
  return Liability(
    id: id,
    type: type,
    name: name,
    principal: d(principal),
    interestRate: d('0.045'),
    currency: currency,
    sync: _meta(),
  );
}

LiabilitySummary _summary(Liability liability, {required String remaining}) {
  final scheduledPrincipal = liability.principal;
  return LiabilitySummary(
    liability: liability,
    totalScheduledPrincipal: scheduledPrincipal,
    totalScheduledInterest: Decimal.zero,
    principalPaid: scheduledPrincipal - d(remaining),
    interestPaid: Decimal.zero,
    remainingPrincipal: d(remaining),
    paidPeriods: 0,
    totalPeriods: 12,
  );
}

CurrencyConverter _converter([List<dom.FxRate> rates = const []]) =>
    FxRateCurrencyConverter(InMemoryFxRateLookup(rates));

DashboardAggregator _aggregator({
  CurrencyConverter? converter,
  String base = 'CNY',
  void Function(String, String)? onMismatch,
}) {
  return DashboardAggregator(
    converter: converter ?? _converter(),
    baseCurrency: base,
    asOf: day(2026, 4, 29),
    onCurrencyMismatch: onMismatch,
  );
}

void main() {
  group('DashboardAggregator', () {
    test('empty inputs produce an empty snapshot at zero', () {
      final snap = _aggregator().aggregate(
        manualAssets: const [],
        physicalAssets: const [],
        liabilities: const [],
        liabilitySummaries: const [],
      );
      expect(snap.allocations, isEmpty);
      expect(snap.totalAssets.amount, Decimal.zero);
      expect(snap.totalLiabilities.amount, Decimal.zero);
      expect(snap.netWorth.amount, Decimal.zero);
      expect(snap.isEmpty, isTrue);
    });

    test('groups manual assets into the right big-bucket category', () {
      final snap = _aggregator().aggregate(
        manualAssets: [
          _manualAsset(
            id: 'cash-1',
            type: AssetType.cash,
            price: '10000',
            name: '工资卡',
          ),
          _manualAsset(
            id: 'demand-1',
            type: AssetType.bankDepositDemand,
            price: '5000',
            name: '活期',
          ),
          _manualAsset(
            id: 'wealth-1',
            type: AssetType.wealthProduct,
            price: '20000',
            name: '理财',
          ),
        ],
        physicalAssets: const [],
        liabilities: const [],
        liabilitySummaries: const [],
      );
      final categories =
          snap.allocations.map((a) => a.category).toList();
      expect(categories, [
        AssetCategory.bondsAndFunds, // wealth + demand deposit > cash
        AssetCategory.cash,
      ]);
      // Cash bucket holds only the pure-cash row.
      final cashBucket = snap.allocations.firstWhere(
        (a) => a.category == AssetCategory.cash,
      );
      expect(cashBucket.items.single.id, 'cash-1');
      // Bonds & funds bucket merges deposits + wealth products, sorted desc.
      final fundsBucket = snap.allocations.firstWhere(
        (a) => a.category == AssetCategory.bondsAndFunds,
      );
      expect(fundsBucket.items.map((i) => i.id), ['wealth-1', 'demand-1']);
    });

    test('liabilities use remaining principal and stay unsigned', () {
      final mortgage = _liability(
        id: 'L1',
        name: '房贷',
        principal: '1000000',
      );
      final snap = _aggregator().aggregate(
        manualAssets: [
          _manualAsset(id: 'cash', type: AssetType.cash, price: '500000'),
        ],
        physicalAssets: const [],
        liabilities: [mortgage],
        liabilitySummaries: [_summary(mortgage, remaining: '650000')],
      );
      final liabAlloc = snap.allocations
          .firstWhere((a) => a.category == AssetCategory.liability);
      expect(liabAlloc.totalInBase.amount, d('650000'));
      // Net worth subtracts the liability total.
      expect(snap.totalAssets.amount, d('500000'));
      expect(snap.totalLiabilities.amount, d('650000'));
      expect(snap.netWorth.amount, d('-150000'));
    });

    test('multi-currency rolls up via the FX converter', () {
      final converter = _converter([
        dom.FxRate(
          base: 'USD',
          quote: 'CNY',
          date: day(2026, 4, 28),
          rate: d('7.2'),
          source: 'test',
        ),
      ]);
      final snap = _aggregator(converter: converter).aggregate(
        manualAssets: [
          _manualAsset(
            id: 'cash-cny',
            type: AssetType.cash,
            currency: 'CNY',
            price: '10000',
          ),
          _manualAsset(
            id: 'cash-usd',
            type: AssetType.cash,
            currency: 'USD',
            price: '1000',
          ),
        ],
        physicalAssets: const [],
        liabilities: const [],
        liabilitySummaries: const [],
      );
      final cashAlloc = snap.allocations.single;
      expect(cashAlloc.totalInBase.amount, d('17200.0'));
      // The native amount is preserved per item.
      final usdItem =
          cashAlloc.items.firstWhere((i) => i.id == 'cash-usd');
      expect(usdItem.nativeCurrency, 'USD');
      expect(usdItem.nativeAmount, d('1000'));
    });

    test('unknown FX pair drops the asset and surfaces it via callback', () {
      final dropped = <String, String>{};
      final agg = _aggregator(
        // empty FX table → USD→CNY conversion will fail
        onMismatch: (id, ccy) => dropped[id] = ccy,
      );
      final snap = agg.aggregate(
        manualAssets: [
          _manualAsset(
            id: 'cny',
            type: AssetType.cash,
            currency: 'CNY',
            price: '10000',
          ),
          _manualAsset(
            id: 'usd-orphan',
            type: AssetType.cash,
            currency: 'USD',
            price: '1000',
          ),
        ],
        physicalAssets: const [],
        liabilities: const [],
        liabilitySummaries: const [],
      );
      final items = snap.allocations.single.items;
      expect(items, hasLength(1));
      expect(items.single.id, 'cny');
      expect(dropped, {'usd-orphan': 'USD'});
    });

    test('skips zero-balance liabilities and zero-priced assets', () {
      final paidOff = _liability(
        id: 'paid',
        name: 'paid',
        principal: '100000',
      );
      final snap = _aggregator().aggregate(
        manualAssets: [
          _manualAsset(id: 'zero', type: AssetType.cash, price: '0'),
          _manualAsset(id: 'live', type: AssetType.cash, price: '500'),
        ],
        physicalAssets: const [],
        liabilities: [paidOff],
        liabilitySummaries: [_summary(paidOff, remaining: '0')],
      );
      // Only the live cash row survives; no liability bucket.
      final cash = snap.allocations.single;
      expect(cash.category, AssetCategory.cash);
      expect(cash.items.single.id, 'live');
      expect(snap.totalLiabilities.amount, Decimal.zero);
    });

    test('physical assets land in their own buckets at current valuation',
        () {
      final snap = _aggregator().aggregate(
        manualAssets: const [],
        physicalAssets: [
          _physicalAsset(
            id: 'house',
            type: AssetType.realEstate,
            purchase: '2000000',
            current: '2500000',
            name: '北京三居',
          ),
          _physicalAsset(
            id: 'car',
            type: AssetType.vehicle,
            purchase: '300000',
            current: '180000',
            name: 'Tesla Model 3',
          ),
        ],
        liabilities: const [],
        liabilitySummaries: const [],
      );
      final cats =
          snap.allocations.map((a) => a.category).toSet();
      expect(cats, {AssetCategory.realEstate, AssetCategory.vehicle});
      expect(snap.totalAssets.amount, d('2680000'));
    });

    test(
      'three-currency portfolio (CNY + USD + HKD) sums to base via FX (FIR-73)',
      () {
        // Mirrors the user-reported scenario in FIR-73:
        //   account A: CNY cash 10000, A-share ETF 50000 RMB
        //   account B: USD cash 5000, AAPL 100 @ 180 = 18000 USD
        //   account C: HKD 0700.HK 100 @ 320 = 32000 HKD
        // Base = CNY, USD/CNY = 7.2, HKD/CNY = 0.92.
        final converter = _converter([
          dom.FxRate(
            base: 'USD',
            quote: 'CNY',
            date: day(2026, 4, 28),
            rate: d('7.2'),
            source: 'test',
          ),
          dom.FxRate(
            base: 'HKD',
            quote: 'CNY',
            date: day(2026, 4, 28),
            rate: d('0.92'),
            source: 'test',
          ),
        ]);
        final snap = _aggregator(converter: converter).aggregate(
          manualAssets: [
            _manualAsset(
              id: 'cny-cash',
              type: AssetType.cash,
              currency: 'CNY',
              price: '10000',
            ),
            _manualAsset(
              id: 'a-share-etf',
              type: AssetType.etf,
              currency: 'CNY',
              price: '50000',
            ),
            _manualAsset(
              id: 'usd-cash',
              type: AssetType.cash,
              currency: 'USD',
              price: '5000',
            ),
            _manualAsset(
              id: 'aapl',
              type: AssetType.stock,
              currency: 'USD',
              price: '18000',
            ),
            _manualAsset(
              id: 'tencent',
              type: AssetType.stock,
              currency: 'HKD',
              price: '32000',
            ),
          ],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySummaries: const [],
        );
        // 10000 + 50000 + 5000*7.2 + 18000*7.2 + 32000*0.92
        // = 60000 + 36000 + 129600 + 29440 = 255040
        expect(snap.totalAssets.amount, d('255040.00'));
        expect(snap.netWorth.amount, d('255040.00'));
        expect(snap.currencyMismatches, isEmpty);
        // Native amounts are preserved per item — the drill-down sheet
        // needs them to render the "USD 5000" subtitle.
        final usdItem = snap.allocations
            .expand((a) => a.items)
            .firstWhere((i) => i.id == 'usd-cash');
        expect(usdItem.nativeCurrency, 'USD');
        expect(usdItem.nativeAmount, d('5000'));
      },
    );

    test('snapshot.currencyMismatches lists every excluded holding (FIR-73)',
        () {
      final agg = _aggregator();
      final snap = agg.aggregate(
        manualAssets: [
          _manualAsset(id: 'cny', type: AssetType.cash, price: '1000'),
          _manualAsset(
            id: 'usd-orphan',
            type: AssetType.cash,
            currency: 'USD',
            price: '1000',
          ),
          _manualAsset(
            id: 'hkd-orphan',
            type: AssetType.cash,
            currency: 'HKD',
            price: '5000',
          ),
        ],
        physicalAssets: const [],
        liabilities: const [],
        liabilitySummaries: const [],
      );
      expect(
        snap.currencyMismatches.map((m) => '${m.id}:${m.currency}').toSet(),
        {'usd-orphan:USD', 'hkd-orphan:HKD'},
      );
      // Banner copy uses the count to drive the plural form.
      expect(snap.currencyMismatches, hasLength(2));
      // CNY total still includes the survivor.
      expect(snap.totalAssets.amount, d('1000'));
    });

    test(
      'switching base currency to USD recomputes every total via inverse FX',
      () {
        // The provider rewires baseCurrency on user setting changes; this
        // test exercises that the math is symmetric — given the same
        // portfolio, asking for totals in USD instead of CNY produces a
        // proportionally smaller number.
        final converter = _converter([
          dom.FxRate(
            base: 'USD',
            quote: 'CNY',
            date: day(2026, 4, 28),
            rate: d('7.2'),
            source: 'test',
          ),
        ]);
        final inUsd = DashboardAggregator(
          converter: converter,
          baseCurrency: 'USD',
          asOf: day(2026, 4, 29),
        ).aggregate(
          manualAssets: [
            _manualAsset(
              id: 'cny-cash',
              type: AssetType.cash,
              currency: 'CNY',
              price: '7200',
            ),
            _manualAsset(
              id: 'usd-cash',
              type: AssetType.cash,
              currency: 'USD',
              price: '1000',
            ),
          ],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySummaries: const [],
        );
        // 7200 CNY * (1/7.2) USD/CNY + 1000 USD = 1000 + 1000 = 2000 USD.
        expect(inUsd.baseCurrency, 'USD');
        // The inverse rate is computed via Decimal so we tolerate a small
        // rounding tail from the 1/7.2 series.
        final total = inUsd.totalAssets.amount.toDouble();
        expect(total, closeTo(2000.0, 0.0001));
      },
    );
  });
}
