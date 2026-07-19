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

enum FinancialSignalRevalidationStatus {
  cleared,
  stillDetected,
  inconclusive,
  actionDropped,
}

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
    this.revalidationStatus,
    this.revalidatedAt,
    this.actionCompletedAt,
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
  final FinancialSignalRevalidationStatus? revalidationStatus;
  final DateTime? revalidatedAt;
  final DateTime? actionCompletedAt;
}

final class FinancialSignalRevalidationReport {
  const FinancialSignalRevalidationReport({
    this.actionCompleted = 0,
    this.cleared = 0,
    this.stillDetected = 0,
    this.inconclusive = 0,
    this.actionDropped = 0,
  });

  final int actionCompleted;
  final int cleared;
  final int stillDetected;
  final int inconclusive;
  final int actionDropped;

  int get processed => cleared + stillDetected + inconclusive + actionDropped;
}
