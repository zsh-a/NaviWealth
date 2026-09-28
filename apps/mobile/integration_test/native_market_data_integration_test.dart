// Explicit live-network smoke: flutter test integration_test/native_market_data_integration_test.dart
//   -d <android-device-or-macos> --dart-define=LIVE_MARKET_DATA=true
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/market/native/native_market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native FRB quotes, raw history and Drift cache',
    (_) async {
      final db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) async => db)],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final service = await container.read(marketDataServiceProvider.future);
      expect(service, isA<NativeMarketDataService>());
      for (final symbol in ['600519.SH', '000001.SZ', '920002.BJ']) {
        final quote = await service.getQuote(symbol, market: AssetMarket.cnA);
        expect(quote.data.price, greaterThan(Decimal.zero));
        expect(quote.data.symbol, symbol);
        expect(quote.source, isIn(['tencent', 'sina']));
        debugPrint(
          'market-smoke: $symbol source=${quote.source} observed=${quote.data.asOf}',
        );
      }
      final cached = await service.getQuote(
        'SH600519',
        market: AssetMarket.cnA,
      );
      expect(cached.freshness, DataFreshness.cachedFresh);
      final now = DateTime.now().toUtc();
      final to = DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 7));
      final history = await service.getHistorical(
        '600519',
        from: to.subtract(const Duration(days: 30)),
        to: to,
        market: AssetMarket.cnA,
      );
      expect(history.data.length, greaterThan(10));
      expect(history.data.every((bar) => bar.symbol == '600519'), isTrue);
      expect(
        history.data.every((bar) => bar.asOf.hour == 0 && bar.asOf.isUtc),
        isTrue,
      );
      expect(history.diagnostics['adjustment'], 'raw');
      expect(history.diagnostics['coverage'], isNotNull);
      debugPrint(
        'market-smoke: history source=${history.source} bars=${history.data.length}',
      );
    },
    skip:
        !(Platform.isAndroid || Platform.isMacOS) ||
        !const bool.fromEnvironment('LIVE_MARKET_DATA'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
