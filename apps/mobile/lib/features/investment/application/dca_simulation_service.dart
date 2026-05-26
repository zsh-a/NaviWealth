import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/async/async_notifier_convention.dart';
import '../../../domain/entities/historical_bar.dart';
import '../../../domain/services/market_data_service.dart';
import '../../../domain/values/asset_market.dart';
import '../../../features/finance/data/market/market_data_providers.dart';
import '../domain/dca/dca_simulator.dart';

final dcaSimulationProvider =
    AsyncNotifierProvider<DcaSimulationNotifier, DcaSimulationState>(
      DcaSimulationNotifier.new,
    );

class DcaSimulationRequest {
  const DcaSimulationRequest({
    required this.symbols,
    required this.market,
    required this.amountPerContribution,
    required this.currency,
    required this.years,
    required this.frequency,
  });

  final List<String> symbols;
  final AssetMarket market;
  final Decimal amountPerContribution;
  final String currency;
  final int years;
  final DcaFrequency frequency;

  DcaSimulationRequest copyWith({
    List<String>? symbols,
    AssetMarket? market,
    Decimal? amountPerContribution,
    String? currency,
    int? years,
    DcaFrequency? frequency,
  }) {
    return DcaSimulationRequest(
      symbols: symbols ?? this.symbols,
      market: market ?? this.market,
      amountPerContribution:
          amountPerContribution ?? this.amountPerContribution,
      currency: currency ?? this.currency,
      years: years ?? this.years,
      frequency: frequency ?? this.frequency,
    );
  }
}

class DcaSimulationState {
  const DcaSimulationState({
    required this.request,
    required this.result,
    required this.freshness,
  });

  final DcaSimulationRequest request;
  final DcaSimulationResult result;
  final DataFreshness freshness;

  bool get isStale => freshness == DataFreshness.stale;
}

class DcaSimulationNotifier
    extends ConventionalAsyncNotifier<DcaSimulationState> {
  DcaSimulationRequest _request = DcaSimulationRequest(
    symbols: ['VOO'],
    market: AssetMarket.usStock,
    amountPerContribution: Decimal.fromInt(500),
    currency: 'USD',
    years: 5,
    frequency: DcaFrequency.monthly,
  );

  @override
  Future<DcaSimulationState> fetch() => _simulate(_request);

  Future<void> run(DcaSimulationRequest request) async {
    _request = request;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _simulate(request));
  }

  Future<DcaSimulationState> _simulate(DcaSimulationRequest request) async {
    final market = await ref.watch(marketDataServiceProvider.future);
    final now = ref.watch(clockProvider).now().toUtc();
    final to = DateTime.utc(now.year, now.month);
    final from = DateTime.utc(to.year - request.years, to.month);
    final symbols = _normalizedSymbols(request.symbols);
    final perSymbolWeight = symbols.isEmpty
        ? Decimal.zero
        : (Decimal.one / Decimal.fromInt(symbols.length)).toDecimal(
            scaleOnInfinitePrecision: 16,
          );

    var combinedFreshness = DataFreshness.cachedFresh;
    final priceSeries = <String, List<DcaPricePoint>>{};
    for (final symbol in symbols) {
      final response = await market.getHistorical(
        symbol,
        from: from,
        to: to,
        interval: BarInterval.month,
        market: request.market,
      );
      combinedFreshness = _leastFresh(combinedFreshness, response.freshness);
      final points = [
        for (final bar in response.data)
          DcaPricePoint(asOf: bar.asOf, close: bar.adjustedClose ?? bar.close),
      ];
      priceSeries[symbol] = points;
    }

    final result = const DcaSimulator().simulate(
      DcaSimulationInput(
        allocations: [
          for (final symbol in symbols)
            DcaAllocation(symbol: symbol, weight: perSymbolWeight),
        ],
        amountPerContribution: request.amountPerContribution,
        currency: request.currency,
        from: from,
        to: to,
        frequency: request.frequency,
        priceSeries: priceSeries,
      ),
    );
    return DcaSimulationState(
      request: request.copyWith(symbols: symbols),
      result: result,
      freshness: combinedFreshness,
    );
  }
}

List<String> _normalizedSymbols(List<String> symbols) {
  final seen = <String>{};
  return [
    for (final symbol in symbols)
      if (symbol.trim().isNotEmpty)
        if (seen.add(symbol.trim().toUpperCase())) symbol.trim().toUpperCase(),
  ];
}

DataFreshness _leastFresh(DataFreshness a, DataFreshness b) {
  int rank(DataFreshness f) => switch (f) {
    DataFreshness.live => 0,
    DataFreshness.cachedFresh => 1,
    DataFreshness.stale => 2,
  };
  return rank(a) >= rank(b) ? a : b;
}
