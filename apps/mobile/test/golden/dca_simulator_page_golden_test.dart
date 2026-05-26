import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/entities/historical_bar.dart';
import 'package:naviwealth/domain/entities/quote.dart';
import 'package:naviwealth/domain/entities/symbol_info.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/investment/presentation/dca_simulator_page.dart';

import '_golden_setup.dart';

Decimal d(String value) => Decimal.parse(value);

class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime now() => DateTime.utc(2026, 5, 18);

  @override
  Future<void> sleep(Duration duration) async {}
}

class _GoldenMarketDataService implements MarketDataService {
  const _GoldenMarketDataService();

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    return MarketResponse(
      data: [
        for (var i = 0; i < 18; i++)
          HistoricalBar(
            symbol: symbol,
            asOf: DateTime.utc(2024 + (i ~/ 12), 1 + (i % 12)),
            open: d('${100 + i * 3}'),
            high: d('${103 + i * 3}'),
            low: d('${98 + i * 3}'),
            close: d('${100 + i * 3}'),
          ),
      ],
      freshness: DataFreshness.cachedFresh,
      source: 'golden-cache',
      fetchedAt: DateTime.utc(2026, 5, 18),
    );
  }

  @override
  Future<MarketResponse<Quote>> getQuote(String symbol, {AssetMarket? market}) {
    throw UnimplementedError();
  }

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  runAllVariants('dca_simulator_page', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'dca_simulator_page',
      variant: variant,
      overrides: [
        clockProvider.overrideWithValue(const _FixedClock()),
        marketDataServiceProvider.overrideWith(
          (_) async => const _GoldenMarketDataService(),
        ),
      ],
      child: const DcaSimulatorPage(),
    );
  });
}
