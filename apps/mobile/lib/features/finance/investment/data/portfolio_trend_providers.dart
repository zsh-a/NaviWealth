import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/portfolio_trend.dart';
import 'investment_portfolio_providers.dart';
import 'portfolio_trend_service.dart';
import 'providers.dart';

final portfolioMonthlyTrendSummariesProvider =
    FutureProvider.autoDispose<Map<String, PortfolioTrendSeries>>((ref) async {
      final portfolios = await ref.watch(investmentPortfoliosProvider.future);
      final history = await ref.watch(
        portfolioCapitalAssignmentHistoryProvider.future,
      );
      final holdings = await ref.watch(holdingServiceProvider.future);
      final converter = ref.watch(returnsCurrencyConverterProvider);
      final baseCurrency = ref.watch(holdingBaseCurrencyProvider);
      ref.watch(holdingsSnapshotProvider);
      return PortfolioTrendService(
        holdings: holdings,
        converter: converter,
        baseCurrency: baseCurrency,
      ).computeMany(
        portfolios: portfolios,
        assignmentHistory: history,
        range: PortfolioTrendRange.month,
      );
    });

final portfolioTrendProvider = FutureProvider.autoDispose
    .family<PortfolioTrendSeries?, PortfolioTrendRequest>((ref, request) async {
      final portfolios = await ref.watch(investmentPortfoliosProvider.future);
      final portfolio = portfolios
          .where((item) => item.id == request.portfolioId)
          .firstOrNull;
      if (portfolio == null) return null;
      final history = await ref.watch(
        portfolioCapitalAssignmentHistoryProvider.future,
      );
      final holdings = await ref.watch(holdingServiceProvider.future);
      final converter = ref.watch(returnsCurrencyConverterProvider);
      final baseCurrency = ref.watch(holdingBaseCurrencyProvider);
      ref.watch(holdingsSnapshotProvider);
      final result =
          await PortfolioTrendService(
            holdings: holdings,
            converter: converter,
            baseCurrency: baseCurrency,
          ).computeMany(
            portfolios: [portfolio],
            assignmentHistory: history,
            range: request.range,
          );
      return result[portfolio.id];
    });
