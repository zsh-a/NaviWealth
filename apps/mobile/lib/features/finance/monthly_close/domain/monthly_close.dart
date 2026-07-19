enum MonthlyCloseStep {
  importReview,
  inboxClear,
  accountReconcile,
  runwayReview,
  actionReview,
}

enum MonthlyCloseStepState { blocked, ready, verified, overridden }

final class MonthlyCloseEvidence {
  const MonthlyCloseEvidence({required this.states, required this.details});

  final Map<MonthlyCloseStep, MonthlyCloseStepState> states;
  final Map<String, Object?> details;

  bool get isVerified => MonthlyCloseStep.values.every(
    (step) => switch (states[step]) {
      MonthlyCloseStepState.verified ||
      MonthlyCloseStepState.overridden => true,
      _ => false,
    },
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'states': <String, String>{
      for (final entry in states.entries) entry.key.name: entry.value.name,
    },
    'details': details,
  };

  factory MonthlyCloseEvidence.fromJson(Map<String, Object?> json) {
    final rawStates = Map<String, Object?>.from(json['states']! as Map);
    return MonthlyCloseEvidence(
      states: <MonthlyCloseStep, MonthlyCloseStepState>{
        for (final entry in rawStates.entries)
          MonthlyCloseStep.values.byName(entry.key): MonthlyCloseStepState
              .values
              .byName(entry.value! as String),
      },
      details: Map<String, Object?>.from(json['details'] as Map? ?? const {}),
    );
  }
}

final class MonthlyClose {
  const MonthlyClose({
    required this.id,
    required this.periodMonth,
    required this.evidence,
    required this.snapshot,
    required this.status,
    required this.startedAt,
    this.overrideReason,
    this.closedAt,
  });

  final String id;
  final String periodMonth;
  final MonthlyCloseEvidence evidence;
  final Map<String, Object?> snapshot;
  final String status;
  final DateTime startedAt;
  final String? overrideReason;
  final DateTime? closedAt;

  bool get isClosed => closedAt != null;
}
