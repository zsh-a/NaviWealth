import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/asset_market.dart';

void main() {
  group('AssetMarket.wire round-trips', () {
    for (final market in AssetMarket.values) {
      test('${market.name} ↔ ${market.wire}', () {
        expect(assetMarketFromWire(market.wire), market);
      });
    }

    test('canonical wire labels match the documented spec', () {
      expect(AssetMarket.cnA.wire, 'cn_a');
      expect(AssetMarket.hkStock.wire, 'hk_stock');
      expect(AssetMarket.usStock.wire, 'us_stock');
      expect(AssetMarket.crypto.wire, 'crypto');
      expect(AssetMarket.fx.wire, 'fx');
      expect(AssetMarket.unknown.wire, 'unknown');
    });

    test('assetMarketFromWire returns null for unknown labels', () {
      expect(assetMarketFromWire(null), isNull);
      expect(assetMarketFromWire(''), isNull);
      expect(assetMarketFromWire('cnA'), isNull,
          reason: 'camelCase form must not parse — wire is snake_case');
      expect(assetMarketFromWire('garbage'), isNull);
    });
  });

  group('inferAssetMarket', () {
    test('A-share 6-digit numeric → cnA', () {
      expect(inferAssetMarket('600519'), AssetMarket.cnA);
      expect(inferAssetMarket('000001'), AssetMarket.cnA);
    });

    test('.HK suffix → hkStock', () {
      expect(inferAssetMarket('0700.HK'), AssetMarket.hkStock);
      expect(inferAssetMarket('00700.HK'), AssetMarket.hkStock);
      expect(inferAssetMarket('TENCENT.HK'), AssetMarket.hkStock);
    });

    test('plain uppercase letters → usStock', () {
      expect(inferAssetMarket('AAPL'), AssetMarket.usStock);
      expect(inferAssetMarket('GOOGL'), AssetMarket.usStock);
      expect(inferAssetMarket('SPY'), AssetMarket.usStock);
    });

    test('-USD suffix → crypto', () {
      expect(inferAssetMarket('BTC-USD'), AssetMarket.crypto);
      expect(inferAssetMarket('ETH-USD'), AssetMarket.crypto);
    });

    test('anything outside the rules → unknown', () {
      expect(inferAssetMarket('weird thing'), AssetMarket.unknown);
      expect(inferAssetMarket('aapl'), AssetMarket.unknown,
          reason: 'lowercase US ticker is not in the spec — fall back');
      expect(inferAssetMarket('  '), AssetMarket.unknown);
    });
  });
}
