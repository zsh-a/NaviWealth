import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';
import 'package:naviwealth/features/finance/investment/data/portfolio_trend_providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_price_source.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_capital_assignment.dart';
import 'package:naviwealth/features/finance/investment/domain/portfolio_trend.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

Decimal _d(String value) => Decimal.parse(value);

void main() {
  test(
    'portfolio trend reprices sampled holdings from historical bars',
    () async {
      final now = DateTime.now().toUtc();
      final createdAt = now.subtract(const Duration(days: 30));
      final portfolio = InvestmentPortfolio(
        id: 'portfolio',
        name: 'Portfolio',
        baseCurrency: 'USD',
        goalId: null,
        color: null,
        createdAt: createdAt,
        archived: false,
        sync: _meta(now),
      );
      final assignment = PortfolioCapitalAssignment(
        id: 'assignment',
        portfolioId: portfolio.id,
        rebalanceGroupId: 'group',
        sourceKind: PortfolioCapitalSourceKind.lot,
        sourceId: 'lot',
        quantity: null,
        amount: null,
        currency: null,
        assignedAt: createdAt,
        sync: _meta(now),
      );
      final asset = Asset(
        id: 'asset',
        type: AssetType.stock,
        symbol: 'AAPL',
        currency: 'USD',
        name: 'Apple',
        market: AssetMarket.usStock.wire,
        sync: _meta(now),
      );
      final market = _HistoricalMarket([
        _bar('AAPL', now.subtract(const Duration(days: 20)), '100'),
        _bar('AAPL', now.subtract(const Duration(days: 10)), '110'),
        _bar('AAPL', DateTime.utc(now.year, now.month, now.day), '120'),
      ]);
      final holdings = _RepriceableHoldings(createdAt: createdAt);
      final container = ProviderContainer(
        overrides: [
          investmentPortfoliosProvider.overrideWith(
            (_) => Stream.value([portfolio]),
          ),
          portfolioCapitalAssignmentHistoryProvider.overrideWith(
            (_) => Stream.value([assignment]),
          ),
          holdingServiceProvider.overrideWith((_) async => holdings),
          holdingsSnapshotProvider.overrideWith((_) async => const {}),
          allAssetsStreamProvider.overrideWith((_) => Stream.value([asset])),
          marketDataServiceProvider.overrideWith((_) async => market),
          holdingPriceSourceProvider.overrideWith(
            (_) async => InMemoryHoldingPriceSource(const []),
          ),
          returnsCurrencyConverterProvider.overrideWithValue(
            const _SameCurrencyConverter(),
          ),
          holdingBaseCurrencyProvider.overrideWithValue('USD'),
        ],
      );
      addTearDown(container.dispose);

      final provider = portfolioTrendProvider(
        PortfolioTrendRequest(
          portfolioId: portfolio.id,
          range: PortfolioTrendRange.month,
        ),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      final series = await container.read(provider.future);

      expect(series, isNotNull);
      expect(holdings.usedCustomPriceSource, isTrue);
      expect(market.historicalCalls, greaterThan(0));
      expect(series!.currentValue, _d('1200'));
      expect(
        series.points.any((point) => point.marketValueInBase == _d('1100')),
        isTrue,
      );
    },
  );
}

SyncMeta _meta(DateTime now) => SyncMeta(
  ownerUserId: 'user',
  updatedAt: now,
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);

HistoricalBar _bar(String symbol, DateTime asOf, String close) => HistoricalBar(
  symbol: symbol,
  asOf: asOf.toUtc(),
  open: _d(close),
  high: _d(close),
  low: _d(close),
  close: _d(close),
);

class _SameCurrencyConverter implements CurrencyConverter {
  const _SameCurrencyConverter();

  @override
  Money convert(Money amount, String to, {DateTime? on}) {
    if (amount.currency != to) {
      throw FxRateNotFoundError(amount.currency, to, on);
    }
    return amount;
  }
}

class _RepriceableHoldings implements RepriceableSampledHoldingService {
  _RepriceableHoldings({required this.createdAt});

  final DateTime createdAt;
  bool usedCustomPriceSource = false;

  Lot get _lot => Lot(
    id: 'lot',
    openingTransactionId: 'trade',
    accountId: 'broker',
    assetId: 'asset',
    currency: 'USD',
    originalQuantity: _d('10'),
    remainingQuantity: _d('10'),
    costPerUnit: _d('100'),
    openedAt: createdAt,
  );

  HoldingSample _sample(DateTime asOf, HoldingPriceSource prices) {
    final unitPrice = prices.priceFor('asset', asOf: asOf)?.price ?? _d('100');
    final marketValue = unitPrice * _d('10');
    return HoldingSample(
      asOf: asOf.toUtc(),
      lots: [_lot],
      snapshots: {
        'asset': HoldingSnapshot(
          assetId: 'asset',
          quantity: _d('10'),
          costBasisInAssetCurrency: _d('1000'),
          marketValueInAssetCurrency: marketValue,
          assetCurrency: 'USD',
          costBasisInBase: _d('1000'),
          marketValueInBase: marketValue,
          unrealizedPnlInBase: marketValue - _d('1000'),
          weight: Decimal.one,
          baseCurrency: 'USD',
          asOf: asOf,
          unitPriceInAssetCurrency: unitPrice,
        ),
      },
    );
  }

  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      _sample(asOf, InMemoryHoldingPriceSource(const [])).snapshots;

  @override
  Future<List<HoldingSample>> computeAtSamples(
    Iterable<DateTime> dates,
  ) async => dates
      .map((date) => _sample(date, InMemoryHoldingPriceSource(const [])))
      .toList(growable: false);

  @override
  Future<List<HoldingSample>> computeAtSamplesWithPriceSource(
    Iterable<DateTime> dates, {
    required HoldingPriceSource priceSource,
  }) async {
    usedCustomPriceSource = true;
    return dates
        .map((date) => _sample(date, priceSource))
        .toList(growable: false);
  }

  @override
  Future<void> invalidateFrom(DateTime from) async {}

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => [_lot];

  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) async =>
      LotInventorySnapshot(ownerUserId: 'user', day: day, lots: [_lot]);
}

class _HistoricalMarket implements MarketDataService {
  _HistoricalMarket(this.bars);

  final List<HistoricalBar> bars;
  int historicalCalls = 0;

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    historicalCalls += 1;
    return MarketResponse(
      data: [
        for (final bar in bars)
          if (bar.symbol == symbol &&
              !bar.asOf.isBefore(from) &&
              !bar.asOf.isAfter(to))
            bar,
      ],
      freshness: DataFreshness.live,
      source: 'history-test',
      fetchedAt: to,
    );
  }

  @override
  Future<MarketResponse<Quote>> getQuote(
    String symbol, {
    AssetMarket? market,
  }) => throw UnimplementedError();

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) => throw UnimplementedError();
}
