part of 'scan_orchestrator.dart';

List<String> _universeExclusionReasons({
  required ApprovedUnderlying approved,
  required Set<OptionsStrategyKind> allowedStrategies,
  required int shares,
}) {
  final reasons = <String>[];
  if (!approved.allowPut) {
    reasons.add('put_not_allowed');
  } else if (!allowedStrategies.contains(OptionsStrategyKind.cashSecuredPut)) {
    reasons.add('cash_secured_put_strategy_disabled');
  }
  if (!approved.allowCall) {
    reasons.add('call_not_allowed');
  } else if (!allowedStrategies.contains(OptionsStrategyKind.coveredCall)) {
    reasons.add('covered_call_strategy_disabled');
  } else if (shares < 100) {
    reasons.add('covered_call_needs_100_shares_have_$shares');
  }
  return reasons;
}

String _formatReasonCounts(Iterable<RejectedCandidate> rejected) {
  final counts = <String, int>{};
  for (final candidate in rejected) {
    for (final reason in candidate.reasons) {
      counts.update(reason, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  if (counts.isEmpty) return '{}';
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  return entries.take(8).map((e) => '${e.key}:${e.value}').join(', ');
}

String _pct(Decimal value) => '${(value * Decimal.fromInt(100)).toString()}%';

String? _quoteQualityWarning(
  OptionsChainSnapshot snapshot, {
  required int minOpenInterest,
}) {
  if (snapshot.contracts.isEmpty) return null;
  final total = snapshot.contracts.length;
  final oiBelowFloor = snapshot.contracts
      .where((contract) => contract.openInterest < minOpenInterest)
      .length;
  final emptyQuotes = snapshot.contracts
      .where(
        (contract) =>
            contract.bid.amount <= Decimal.zero &&
            contract.ask.amount <= Decimal.zero,
      )
      .length;
  final allQuoteEmpty = emptyQuotes >= total;
  final allOpenInterestUnavailable = _openInterestUnavailable(snapshot);
  final allOiBelowFloor = oiBelowFloor >= total;
  if (!allQuoteEmpty && !allOpenInterestUnavailable && !allOiBelowFloor) {
    return null;
  }
  final details = <String>[];
  if (allQuoteEmpty) details.add('all contracts have empty bid/ask quotes');
  if (allOpenInterestUnavailable) {
    details.add('open interest appears unavailable from source');
  } else if (allOiBelowFloor) {
    details.add('all contracts are below OI floor');
  }
  return 'Quote quality warning: ${details.join("; ")}. '
      'The chain was fetched successfully, but current tradable quotes '
      'are unavailable or too sparse.';
}

bool _openInterestUnavailable(OptionsChainSnapshot snapshot) {
  final contracts = snapshot.contracts;
  if (contracts.isEmpty) return false;
  final positive = contracts.where((c) => c.openInterest > 0).length;
  final toleratedSparsePositiveCount = (contracts.length * 0.05).floor();
  return positive <= toleratedSparsePositiveCount;
}
