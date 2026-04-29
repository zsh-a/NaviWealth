import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/providers.dart';
import '../../../data/db/providers.dart';
import '../../../data/market/market_data_providers.dart';
import '../../../data/repositories/mutation_context.dart';
import '../../../data/repositories/providers.dart';
import '../../../domain/services/currency_converter.dart';
import '../domain/trade_entry/default_trade_entry_service.dart';
import '../domain/trade_entry/trade_entry_service.dart';
import 'transaction_repository.dart';

final transactionRepositoryProvider =
    FutureProvider<TransactionRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return TransactionRepository(db: db, outbox: outbox, stamper: stamper);
});

/// Currency converter for trade-entry FX backfill.
/// Uses the same stub as the dashboard until a persistent FX rate repo ships.
final _tradeCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  return FxRateCurrencyConverter(InMemoryFxRateLookup(const []));
});

final tradeEntryServiceProvider = FutureProvider<TradeEntryService>((ref) async {
  final market = await ref.watch(marketDataServiceProvider.future);
  final fx = ref.watch(_tradeCurrencyConverterProvider);
  final engine = await ref.watch(syncEngineProvider.future);
  final deviceId = ref.watch(deviceIdProviderProvider);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return DefaultTradeEntryService(
    market: market,
    fx: fx,
    stampHlc: engine.stampHlc,
    ownerUserId: await stamper.currentUserId(),
    deviceId: await deviceId.getOrCreate(),
  );
});
