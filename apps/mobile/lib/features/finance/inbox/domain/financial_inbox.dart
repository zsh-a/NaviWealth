enum FinancialInboxKind {
  importReview,
  runwayRisk,
  missingExchangeRate,
  balanceMismatch,
  expenseAnomaly,
  subscriptionChange,
  staleValuation,
  decisionReview,
}

enum FinancialInboxPriority { attention, important }

enum FinancialSignalStatus { open, snoozed, resolved }

final class FinancialSignalCandidate {
  const FinancialSignalCandidate({
    required this.sourceKey,
    required this.kind,
    required this.priority,
    required this.count,
    required this.route,
    this.evidence = const <String, Object?>{},
  });

  final String sourceKey;
  final FinancialInboxKind kind;
  final FinancialInboxPriority priority;
  final int count;
  final String route;
  final Map<String, Object?> evidence;
}

final class FinancialInboxItem {
  const FinancialInboxItem({
    required this.id,
    required this.sourceKey,
    required this.kind,
    required this.priority,
    required this.count,
    required this.route,
    required this.evidence,
    required this.firstDetectedAt,
    required this.lastDetectedAt,
    this.actionId,
  });

  final String id;
  final String sourceKey;
  final FinancialInboxKind kind;
  final FinancialInboxPriority priority;
  final int count;
  final String route;
  final Map<String, Object?> evidence;
  final DateTime firstDetectedAt;
  final DateTime lastDetectedAt;
  final String? actionId;
}
