import 'package:naviwealth/features/finance/investment/domain/models/portfolio_removal_failure.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

String portfolioRemovalErrorMessage(
  AppLocalizations l10n,
  Object error, {
  required String fallback,
}) {
  if (error case PortfolioRemovalException(:final reason)) {
    return switch (reason) {
      PortfolioRemovalFailureReason.lastCapitalStrategy =>
        l10n.portfolioStrategyDeleteLastBlocked,
      PortfolioRemovalFailureReason.portfolioNotActive ||
      PortfolioRemovalFailureReason.strategyNotActive ||
      PortfolioRemovalFailureReason.transferTargetRequired ||
      PortfolioRemovalFailureReason.transferTargetInvalid => fallback,
    };
  }
  return fallback;
}
