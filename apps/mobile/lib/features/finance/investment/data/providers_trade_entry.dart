part of 'providers.dart';

final _tradeCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  return FxRateCurrencyConverter(InMemoryFxRateLookup(const []));
});

/// Deadline for dependency resolution and optional market-price backfill
/// before a trade opens its durable database transaction.
final tradeEntryPreflightTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 12),
);

final tradeEntryServiceProvider = FutureProvider<TradeEntryService>((
  ref,
) async {
  final fx = ref.watch(_tradeCurrencyConverterProvider);
  return DefaultTradeEntryService(
    marketLoader: () => ref.read(marketDataServiceProvider.future),
    marketLookupTimeout: ref.watch(tradeEntryPreflightTimeoutProvider),
    fx: fx,
  );
});

final tradeEntrySubmissionServiceProvider =
    FutureProvider<TradeEntrySubmissionService>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final securitiesRepo = await ref.watch(
        securitiesAssetRepositoryProvider.future,
      );
      final tradeService = await ref.watch(tradeEntryServiceProvider.future);
      final journalEntryRepo = await ref.watch(
        journalEntryRepositoryProvider.future,
      );
      final priceRepo = await ref.watch(priceRepositoryProvider.future);
      return TradeEntrySubmissionService(
        db: db,
        securitiesRepo: securitiesRepo,
        tradeService: tradeService,
        journalEntryRepo: journalEntryRepo,
        priceRepo: priceRepo,
        currentUserId: ref.watch(currentUserIdProvider),
      );
    });
