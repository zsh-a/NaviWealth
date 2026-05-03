import 'xirr_engine.dart';

/// Money-weighted return read model for the securities portfolio.
///
/// Implementations derive every cash flow from the forward ledger
/// (`journal_entries` + `postings`) and use holdings snapshots as the
/// start/end bookends consumed by [XirrEngine].
abstract class PortfolioReturnService {
  Future<PortfolioReturnResult> compute({
    required DateTime from,
    required DateTime to,
  });
}

class PortfolioReturnResult {
  const PortfolioReturnResult({
    required this.from,
    required this.to,
    required this.baseCurrency,
    required this.cashFlows,
    required this.solution,
    this.missingCurrencies = const <String>{},
  });

  final DateTime from;
  final DateTime to;
  final String baseCurrency;
  final List<XirrCashFlow> cashFlows;
  final XirrSolution solution;

  /// Currencies that could not be converted into [baseCurrency]. When this
  /// is non-empty, [displayReturn] is null so callers do not render a
  /// partial return as if it were complete.
  final Set<String> missingCurrencies;

  bool get isComplete => missingCurrencies.isEmpty;

  /// Annualized XIRR when the solver converged; otherwise the cumulative
  /// absolute return fallback. Null means the input was incomplete or the
  /// fallback itself was undefined.
  double? get displayReturn {
    if (!isComplete) return null;
    return switch (solution) {
      XirrConverged(:final rate) => rate,
      XirrFallbackAbsolute(:final absoluteReturn) => absoluteReturn,
    };
  }
}
