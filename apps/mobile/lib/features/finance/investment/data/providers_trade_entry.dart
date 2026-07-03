part of 'providers.dart';

final _tradeCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  return FxRateCurrencyConverter(InMemoryFxRateLookup(const []));
});

final tradeEntryServiceProvider = FutureProvider<TradeEntryService>((
  ref,
) async {
  final market = await ref.watch(marketDataServiceProvider.future);
  final fx = ref.watch(_tradeCurrencyConverterProvider);
  return DefaultTradeEntryService(market: market, fx: fx);
});

final tradeEntrySubmissionServiceProvider =
    FutureProvider<TradeEntrySubmissionService>((ref) async {
      final securitiesRepo = await ref.watch(
        securitiesAssetRepositoryProvider.future,
      );
      final tradeService = await ref.watch(tradeEntryServiceProvider.future);
      final journalEntryRepo = await ref.watch(
        journalEntryRepositoryProvider.future,
      );
      final priceRepo = await ref.watch(priceRepositoryProvider.future);
      return TradeEntrySubmissionService(
        securitiesRepo: securitiesRepo,
        tradeService: tradeService,
        journalEntryRepo: journalEntryRepo,
        priceRepo: priceRepo,
        currentUserId: ref.watch(currentUserIdProvider),
      );
    });
