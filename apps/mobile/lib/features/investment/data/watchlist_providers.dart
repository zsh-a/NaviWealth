import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../core/persistence/providers.dart';
import '../../../domain/entities/quote.dart';
import '../../../domain/services/market_data_service.dart';
import '../../../features/finance/data/market/market_data_providers.dart';
import 'watchlist_repository.dart';

final watchlistRepositoryProvider = FutureProvider<WatchlistRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return WatchlistRepository(db: db, outbox: outbox, stamper: stamper);
});

final watchlistItemsProvider = StreamProvider.autoDispose<List<WatchlistItem>>((
  ref,
) async* {
  final repo = await ref.watch(watchlistRepositoryProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  yield* repo.watchActive(ownerUserId);
});

final watchlistQuoteSnapshotsProvider =
    FutureProvider.autoDispose<List<WatchlistQuoteSnapshot>>((ref) async {
      final items = await ref.watch(watchlistItemsProvider.future);
      if (items.isEmpty) return const [];
      final service = await ref.watch(marketDataServiceProvider.future);
      final snapshots = <WatchlistQuoteSnapshot>[];
      for (final item in items) {
        snapshots.add(await _fetchSnapshot(service, item));
      }
      return snapshots;
    });

class WatchlistQuoteSnapshot {
  const WatchlistQuoteSnapshot({required this.item, this.response, this.error});

  final WatchlistItem item;
  final MarketResponse<Quote>? response;
  final Object? error;

  Quote? get quote => response?.data;
  bool get hasError => error != null;
}

Future<WatchlistQuoteSnapshot> _fetchSnapshot(
  MarketDataService service,
  WatchlistItem item,
) async {
  try {
    final response = await service.getQuote(item.symbol, market: item.market);
    return WatchlistQuoteSnapshot(item: item, response: response);
  } catch (error) {
    return WatchlistQuoteSnapshot(item: item, error: error);
  }
}
