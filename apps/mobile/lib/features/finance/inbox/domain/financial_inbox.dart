enum FinancialInboxKind { importReview, runwayRisk, missingExchangeRate }

enum FinancialInboxPriority { attention, important }

final class FinancialInboxItem {
  const FinancialInboxItem({
    required this.id,
    required this.kind,
    required this.priority,
    required this.count,
    required this.route,
  });

  final String id;
  final FinancialInboxKind kind;
  final FinancialInboxPriority priority;
  final int count;
  final String route;
}
