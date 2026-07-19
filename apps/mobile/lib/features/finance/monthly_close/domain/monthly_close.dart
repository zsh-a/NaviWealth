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

final class MonthlyCloseComparison {
  const MonthlyCloseComparison({
    required this.newSignalKeys,
    required this.clearedSignalKeys,
    required this.previousDuration,
  });

  final Set<String> newSignalKeys;
  final Set<String> clearedSignalKeys;
  final Duration? previousDuration;

  bool get hasPrevious =>
      previousDuration != null ||
      newSignalKeys.isNotEmpty ||
      clearedSignalKeys.isNotEmpty;
}

MonthlyCloseComparison compareMonthlyCloseEvidence({
  required MonthlyCloseEvidence current,
  required MonthlyClose? previous,
}) {
  final currentSignals = _stringSet(current.details['active_signal_keys']);
  final previousSignals = _stringSet(previous?.snapshot['active_signal_keys']);
  final durationMs = (previous?.snapshot['close_duration_ms'] as num?)?.toInt();
  return MonthlyCloseComparison(
    newSignalKeys: currentSignals.difference(previousSignals),
    clearedSignalKeys: previousSignals.difference(currentSignals),
    previousDuration: durationMs == null
        ? null
        : Duration(milliseconds: durationMs),
  );
}

Set<String> _stringSet(Object? value) => switch (value) {
  Iterable<Object?> values => values.whereType<String>().toSet(),
  _ => <String>{},
};
