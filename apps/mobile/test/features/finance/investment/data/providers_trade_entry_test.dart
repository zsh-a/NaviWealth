import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/auth_state.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/core/sync/sync_engine.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_errors.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../domain/trade_entry/_fakes.dart';

final _session = AuthSession(
  accessToken: 'token',
  expiresAt: DateTime.utc(2099),
  userId: 'user-1',
  deviceId: 'device-1',
);

void main() {
  test(
    'production trade providers do not wait for sync or unused market data',
    () async {
      SharedPreferences.setMockInitialValues(const {});
      final preferences = await SharedPreferences.getInstance();
      final db = makeTestDatabase();
      final syncGate = Completer<SyncEngine?>();
      final marketGate = Completer<MarketDataService>();
      var syncProviderReads = 0;
      var marketProviderReads = 0;
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWithValue(AuthLoggedIn(_session)),
          sharedPreferencesProvider.overrideWithValue(preferences),
          appDatabaseProvider.overrideWith((ref) async => db),
          syncEngineProvider.overrideWith((ref) {
            syncProviderReads++;
            return syncGate.future;
          }),
          marketDataServiceProvider.overrideWith((ref) {
            marketProviderReads++;
            return marketGate.future;
          }),
          tradeEntryPreflightTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      final submission = await container
          .read(tradeEntrySubmissionServiceProvider.future)
          .timeout(const Duration(seconds: 2));

      expect(submission.isBoundTo(db), isTrue);
      expect(syncProviderReads, 0);
      expect(marketProviderReads, 0);

      final stamper = await container.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      expect(stamp.ownerUserId, _session.userId);
      expect(stamp.deviceId, _session.deviceId);
      expect(stamp.hlc.nodeId, _session.deviceId);
      expect(syncProviderReads, 0);

      final tradeService = await container.read(
        tradeEntryServiceProvider.future,
      );
      await expectLater(
        tradeService.buildPlan(
          TradeDraft(
            type: TradeType.buy,
            asset: asset(market: 'us_stock'),
            accountId: 'broker',
            quantity: Decimal.one,
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 7, 11),
          ),
          openLots: const [],
        ),
        throwsA(
          isA<TradeEntryException>().having(
            (error) => error.code,
            'code',
            TradeEntryErrorCode.priceUnavailable,
          ),
        ),
      );
      expect(marketProviderReads, 1);
      expect(syncProviderReads, 0);
    },
  );
}
