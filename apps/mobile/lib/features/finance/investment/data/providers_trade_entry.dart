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
