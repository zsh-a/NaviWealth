import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../domain/portfolio_trend.dart';
import 'historical_holding_price_source.dart';
import 'investment_portfolio_providers.dart';
import 'portfolio_trend_service.dart';
import 'providers.dart';

final portfolioMonthlyTrendSummariesProvider =
    FutureProvider.autoDispose<Map<String, PortfolioTrendSeries>>((ref) async {
      return _loadPortfolioTrends(ref, range: PortfolioTrendRange.month);
    });

final portfolioTrendProvider = FutureProvider.autoDispose
    .family<PortfolioTrendSeries?, PortfolioTrendRequest>((ref, request) async {
      final result = await _loadPortfolioTrends(
        ref,
        range: request.range,
        portfolioId: request.portfolioId,
      );
      return result[request.portfolioId];
    });

Future<Map<String, PortfolioTrendSeries>> _loadPortfolioTrends(
  Ref ref, {
  required PortfolioTrendRange range,
  String? portfolioId,
}) async {
  // Register every reactive edge before the first async gap. A posting change,
  // assignment edit, asset update, or successful quote sync then rebuilds the
  // complete price-and-holdings window instead of leaving a partial snapshot.
  final portfoliosFuture = ref.watch(investmentPortfoliosProvider.future);
  final historyFuture = ref.watch(
    portfolioCapitalAssignmentHistoryProvider.future,
  );
  final holdingsFuture = ref.watch(holdingServiceProvider.future);
  final assetsFuture = ref.watch(allAssetsStreamProvider.future);
  final marketFuture = ref.watch(marketDataServiceProvider.future);
  final currentPricesFuture = ref.watch(holdingPriceSourceProvider.future);
  final converter = ref.watch(returnsCurrencyConverterProvider);
  final baseCurrency = ref.watch(holdingBaseCurrencyProvider);
  ref.watch(holdingsSnapshotProvider);

  final allPortfolios = await portfoliosFuture;
  final portfolios = portfolioId == null
      ? allPortfolios
      : allPortfolios
            .where((portfolio) => portfolio.id == portfolioId)
            .toList(growable: false);
  if (portfolios.isEmpty) return const {};

  final now = DateTime.now().toUtc();
  final sampleDates = [
    for (final portfolio in portfolios)
      ...PortfolioTrendService.sampleDatesFor(
        createdAt: portfolio.createdAt,
        end: now,
        range: range,
      ),
  ];
  final from = sampleDates.reduce((a, b) => a.isBefore(b) ? a : b);
  final to = sampleDates.reduce((a, b) => a.isAfter(b) ? a : b);
  final assets = await assetsFuture;
  final priceSource = await buildHistoricalHoldingPriceSource(
    market: await marketFuture,
    current: await currentPricesFuture,
    assets: assets.where((asset) => kSecuritiesAssetTypes.contains(asset.type)),
    from: from,
    to: to,
  );

  return PortfolioTrendService(
    holdings: await holdingsFuture,
    converter: converter,
    baseCurrency: baseCurrency,
  ).computeMany(
    portfolios: portfolios,
    assignmentHistory: await historyFuture,
    range: range,
    priceSource: priceSource,
    now: now,
  );
}
