enum MonthlyCloseStep {
  importReview,
  inboxClear,
  accountReconcile,
  runwayReview,
  actionReview,
}

final class MonthlyClose {
  const MonthlyClose({
    required this.id,
    required this.periodMonth,
    required this.completedSteps,
    required this.startedAt,
    this.closedAt,
  });

  final String id;
  final String periodMonth;
  final Set<MonthlyCloseStep> completedSteps;
  final DateTime startedAt;
  final DateTime? closedAt;

  bool get isComplete => MonthlyCloseStep.values.every(completedSteps.contains);
}
