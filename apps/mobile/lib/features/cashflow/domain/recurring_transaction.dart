import '../../../data/domain/sync_meta.dart';

class RecurringTransaction {
  const RecurringTransaction({
    required this.id,
    required this.templateJournalBuildJson,
    required this.rrule,
    required this.nextDueAt,
    this.lastMaterialisedAt,
    required this.enabled,
    required this.sync,
  });

  final String id;
  final String templateJournalBuildJson;
  final String rrule;
  final DateTime nextDueAt;
  final DateTime? lastMaterialisedAt;
  final bool enabled;
  final SyncMeta sync;

  RecurringTransaction copyWith({
    String? templateJournalBuildJson,
    String? rrule,
    DateTime? nextDueAt,
    DateTime? lastMaterialisedAt,
    bool? enabled,
    SyncMeta? sync,
  }) {
    return RecurringTransaction(
      id: id,
      templateJournalBuildJson:
          templateJournalBuildJson ?? this.templateJournalBuildJson,
      rrule: rrule ?? this.rrule,
      nextDueAt: nextDueAt ?? this.nextDueAt,
      lastMaterialisedAt: lastMaterialisedAt ?? this.lastMaterialisedAt,
      enabled: enabled ?? this.enabled,
      sync: sync ?? this.sync,
    );
  }
}

class ForecastedRecurringEvent {
  const ForecastedRecurringEvent({
    required this.recurringTransactionId,
    required this.occurrenceDate,
    required this.templateJournalBuildJson,
  });

  final String recurringTransactionId;
  final DateTime occurrenceDate;
  final String templateJournalBuildJson;

  bool get isForecast => true;
}
