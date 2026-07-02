import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/analytics/domain/equity_allocation.dart';
import 'package:naviwealth/features/finance/analytics/domain/equity_classification.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

const _user = 'user-1';
const _baseCurrency = 'USD';
final _asOf = DateTime.utc(2026, 4, 28);

Decimal _d(String s) => Decimal.parse(s);

Asset _equity({
  required String id,
  required String symbol,
  AssetType type = AssetType.stock,
  String? industry,
  String? region,
  String? market,
}) {
  return Asset(
    id: id,
    type: type,
    symbol: symbol,
    currency: 'USD',
    name: symbol,
    market: market,
    industry: industry,
    region: region,
    sync: SyncMeta(
      ownerUserId: _user,
      updatedAt: DateTime.utc(2026, 1, 1),
      updatedByDevice: 'dev',
      hlc: Hlc.zero('node'),
    ),
  );
}

HoldingSnapshot _snap({
  required String assetId,
  required Decimal mvBase,
  Decimal? quantity,
}) {
  return HoldingSnapshot(
    assetId: assetId,
    quantity: quantity ?? _d('1'),
    costBasisInAssetCurrency: Decimal.zero,
    marketValueInAssetCurrency: mvBase,
    assetCurrency: 'USD',
    costBasisInBase: Decimal.zero,
    marketValueInBase: mvBase,
    unrealizedPnlInBase: Decimal.zero,
    weight: Decimal.zero,
    baseCurrency: _baseCurrency,
    asOf: _asOf,
  );
}

void main() {
  group('EquityAllocationService.aggregate', () {
    test('groups holdings by sector and computes weights', () {
      final assets = {
        'a': _equity(id: 'a', symbol: 'AAPL', industry: 'Technology'),
        'b': _equity(id: 'b', symbol: 'MSFT', industry: 'Technology'),
        'c': _equity(id: 'c', symbol: 'JNJ', industry: 'Healthcare'),
      };
      final snapshots = [
        _snap(assetId: 'a', mvBase: _d('400')),
        _snap(assetId: 'b', mvBase: _d('200')),
        _snap(assetId: 'c', mvBase: _d('400')),
      ];
      final view = const EquityAllocationService().aggregate(
        snapshots: snapshots,
        assetLookup: (id) => assets[id],
        classifier: DefaultEquityClassifier(),
        dimension: EquityAllocationDimension.sector,
        baseCurrency: _baseCurrency,
        asOf: _asOf,
      );

      expect(view.totalValueInBase, _d('1000'));
      expect(view.buckets.length, 2);

      final tech = view.buckets.firstWhere((b) => b.label == 'Technology');
      expect(tech.totalValueInBase, _d('600'));
      expect(tech.weight, _d('0.6'));
      expect(tech.holdings.length, 2);
      // Holdings ordered desc by market value within a bucket.
      expect(tech.holdings.first.symbol, 'AAPL');
      expect(tech.holdings.first.weight, _d('0.4'));

      // Buckets ordered desc by total — tech (600) before healthcare (400).
      expect(view.buckets.first.label, 'Technology');
      expect(view.unclassifiedCount, 0);
    });

    test('skips non-equity asset types', () {
      final assets = {
        'a': _equity(id: 'a', symbol: 'AAPL', industry: 'Technology'),
        'cash': _equity(
          id: 'cash',
          symbol: 'USD',
          type: AssetType.cash,
          industry: 'Currency',
        ),
      };
      final snapshots = [
        _snap(assetId: 'a', mvBase: _d('100')),
        _snap(assetId: 'cash', mvBase: _d('500')),
      ];
      final view = const EquityAllocationService().aggregate(
        snapshots: snapshots,
        assetLookup: (id) => assets[id],
        classifier: DefaultEquityClassifier(),
        dimension: EquityAllocationDimension.sector,
        baseCurrency: _baseCurrency,
        asOf: _asOf,
      );
      expect(view.totalValueInBase, _d('100'));
      expect(view.buckets.single.label, 'Technology');
    });

    test('routes missing sector to unclassified bucket and counts it', () {
      final assets = {
        'a': _equity(id: 'a', symbol: 'AAPL', industry: 'Technology'),
        'b': _equity(id: 'b', symbol: 'XYZ'),
      };
      final snapshots = [
        _snap(assetId: 'a', mvBase: _d('100')),
        _snap(assetId: 'b', mvBase: _d('40')),
      ];
      final view = const EquityAllocationService().aggregate(
        snapshots: snapshots,
        assetLookup: (id) => assets[id],
        classifier: DefaultEquityClassifier(),
        dimension: EquityAllocationDimension.sector,
        baseCurrency: _baseCurrency,
        asOf: _asOf,
      );

      expect(view.unclassifiedCount, 1);
      expect(view.buckets.length, 2);
      // Unclassified bucket sorts last regardless of value.
      expect(view.buckets.last.isUnclassified, isTrue);
      expect(view.buckets.last.label, kUnclassifiedBucketLabel);
      expect(view.buckets.last.totalValueInBase, _d('40'));
      expect(view.buckets.last.holdings.single.symbol, 'XYZ');
    });

    test('region dimension labels by AssetMarket name', () {
      final assets = {
        'a': _equity(id: 'a', symbol: '600519', market: 'sse'),
        'b': _equity(id: 'b', symbol: '0700', market: 'hk'),
      };
      final snapshots = [
        _snap(assetId: 'a', mvBase: _d('300')),
        _snap(assetId: 'b', mvBase: _d('100')),
      ];
      final view = const EquityAllocationService().aggregate(
        snapshots: snapshots,
        assetLookup: (id) => assets[id],
        classifier: DefaultEquityClassifier(),
        dimension: EquityAllocationDimension.region,
        baseCurrency: _baseCurrency,
        asOf: _asOf,
      );
      expect(view.buckets.length, 2);
      expect(view.buckets.first.label, AssetMarket.cnA.name);
      expect(view.buckets.first.weight, _d('0.75'));
    });

    test('marketCap dimension uses bucket key with manual override', () {
      final assets = {
        'a': _equity(id: 'a', symbol: 'BIG'),
        'b': _equity(id: 'b', symbol: 'SMALL'),
        'c': _equity(id: 'c', symbol: 'NONE'),
      };
      final overrides = InMemoryEquityClassificationOverrideStore({
        'a': EquityClassificationOverride(marketCap: _d('500000000000')),
        'b': EquityClassificationOverride(marketCap: _d('1000000000')),
      });
      final view = const EquityAllocationService().aggregate(
        snapshots: [
          _snap(assetId: 'a', mvBase: _d('800')),
          _snap(assetId: 'b', mvBase: _d('150')),
          _snap(assetId: 'c', mvBase: _d('50')),
        ],
        assetLookup: (id) => assets[id],
        classifier: DefaultEquityClassifier(overrides: overrides),
        dimension: EquityAllocationDimension.marketCap,
        baseCurrency: _baseCurrency,
        asOf: _asOf,
      );

      expect(view.buckets.length, 3);
      expect(view.buckets.first.label, MarketCapBucket.large.name);
      expect(view.buckets.first.totalValueInBase, _d('800'));
      expect(view.buckets[1].label, MarketCapBucket.small.name);
      expect(view.buckets.last.isUnclassified, isTrue);
      expect(view.unclassifiedCount, 1);
    });

    test('returns empty view when no holdings supplied', () {
      final view = const EquityAllocationService().aggregate(
        snapshots: const [],
        assetLookup: (_) => null,
        classifier: DefaultEquityClassifier(),
        dimension: EquityAllocationDimension.sector,
        baseCurrency: _baseCurrency,
        asOf: _asOf,
      );
      expect(view.isEmpty, isTrue);
      expect(view.totalValueInBase, Decimal.zero);
    });

    test('skips zero / negative market value snapshots', () {
      final assets = {'a': _equity(id: 'a', symbol: 'A', industry: 'Tech')};
      final view = const EquityAllocationService().aggregate(
        snapshots: [_snap(assetId: 'a', mvBase: Decimal.zero)],
        assetLookup: (id) => assets[id],
        classifier: DefaultEquityClassifier(),
        dimension: EquityAllocationDimension.sector,
        baseCurrency: _baseCurrency,
        asOf: _asOf,
      );
      expect(view.isEmpty, isTrue);
    });
  });
}
