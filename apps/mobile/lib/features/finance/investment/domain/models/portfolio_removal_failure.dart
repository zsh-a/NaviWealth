enum PortfolioRemovalFailureReason {
  lastCapitalStrategy,
  portfolioNotActive,
  strategyNotActive,
  transferTargetRequired,
  transferTargetInvalid,
}

class PortfolioRemovalException implements Exception {
  const PortfolioRemovalException(this.reason);

  final PortfolioRemovalFailureReason reason;

  @override
  String toString() => 'PortfolioRemovalException(${reason.name})';
}
