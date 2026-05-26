import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/analytics/domain/equity_classification.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/hlc.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';

const _user = 'user-1';

Asset _asset({
  required String id,
  String symbol = 'TST',
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

void main() {
  group('MarketCapThresholds.bucket', () {
    final thresholds = MarketCapThresholds.defaults();

    test('classifies values above largeMin as large', () {
      expect(
        thresholds.bucket(Decimal.parse('500000000000')),
        MarketCapBucket.large,
      );
    });

    test('classifies the boundary value largeMin as large', () {
      expect(
        thresholds.bucket(Decimal.parse('200000000000')),
        MarketCapBucket.large,
      );
    });

    test('classifies values between thresholds as mid', () {
      expect(
        thresholds.bucket(Decimal.parse('50000000000')),
        MarketCapBucket.mid,
      );
    });

    test('classifies the boundary value smallMax as small', () {
      expect(
        thresholds.bucket(Decimal.parse('2000000000')),
        MarketCapBucket.small,
      );
    });

    test('returns null for null input — unclassified pipeline', () {
      expect(thresholds.bucket(null), isNull);
    });
  });

  group('DefaultEquityClassifier', () {
    test('returns auto-sourced fields when only the asset has values', () {
      final classifier = DefaultEquityClassifier();
      final classification = classifier.classify(
        _asset(id: 'a', industry: 'Technology', market: 'us'),
      );
      expect(classification.sector.value, 'Technology');
      expect(classification.sector.source, ClassificationSource.auto);
      expect(classification.region.value, AssetMarket.usStock);
      expect(classification.region.source, ClassificationSource.auto);
    });

    test(
      'falls back to "missing" when no override and asset fields are empty',
      () {
        final classifier = DefaultEquityClassifier();
        final classification = classifier.classify(_asset(id: 'a'));
        expect(classification.sector.isMissing, isTrue);
        expect(classification.region.isMissing, isTrue);
        expect(classification.marketCap.isMissing, isTrue);
        expect(classification.marketCapBucket.isMissing, isTrue);
        expect(
          classification.isMissingFor(EquityAllocationDimension.sector),
          isTrue,
        );
      },
    );

    test('manual override beats the asset row, per field', () {
      final overrides = InMemoryEquityClassificationOverrideStore({
        'a': const EquityClassificationOverride(
          sector: 'Healthcare',
          // region omitted on purpose — auto value should still flow through
        ),
      });
      final classifier = DefaultEquityClassifier(overrides: overrides);
      final classification = classifier.classify(
        _asset(id: 'a', industry: 'Technology', market: 'us'),
      );
      expect(classification.sector.value, 'Healthcare');
      expect(classification.sector.source, ClassificationSource.manual);
      expect(classification.region.value, AssetMarket.usStock);
      expect(classification.region.source, ClassificationSource.auto);
    });

    test('region override resolves market-cap bucket against thresholds', () {
      final overrides = InMemoryEquityClassificationOverrideStore({
        'a': EquityClassificationOverride(
          marketCap: Decimal.parse('250000000000'),
        ),
      });
      final classifier = DefaultEquityClassifier(overrides: overrides);
      final classification = classifier.classify(_asset(id: 'a'));
      expect(classification.marketCap.value, Decimal.parse('250000000000'));
      expect(classification.marketCapBucket.value, MarketCapBucket.large);
      expect(
        classification.marketCapBucket.source,
        ClassificationSource.manual,
      );
    });

    test('treats blank sector strings as missing', () {
      final classifier = DefaultEquityClassifier();
      final classification = classifier.classify(
        _asset(id: 'a', industry: '   '),
      );
      expect(classification.sector.isMissing, isTrue);
    });

    test('uses region hint when explicit region column is set', () {
      final classifier = DefaultEquityClassifier();
      final classification = classifier.classify(_asset(id: 'a', region: 'HK'));
      expect(classification.region.value, AssetMarket.hkStock);
    });
  });

  group('assetMarketFromHint', () {
    test('maps common A-share aliases', () {
      for (final hint in ['cn', 'cn-a', 'sse', 'szse', 'A-Shares']) {
        expect(assetMarketFromHint(hint), AssetMarket.cnA, reason: hint);
      }
    });

    test('returns null for unrecognized strings', () {
      expect(assetMarketFromHint('JP'), isNull);
      expect(assetMarketFromHint(''), isNull);
      expect(assetMarketFromHint(null), isNull);
    });
  });
}
