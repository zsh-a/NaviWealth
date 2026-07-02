import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/local_skills.dart';

class RecurringPatternHistoryStore {
  RecurringPatternHistoryStore(this._db);

  final AppDatabase _db;

  Future<void> recordPatterns({
    required String ownerUserId,
    required DateTime observedAt,
    required Iterable<RecurringPattern> patterns,
  }) async {
    final observedAtMs = observedAt.toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      for (final pattern in patterns) {
        final lastSeenMs = pattern.lastSeenAt.toUtc().millisecondsSinceEpoch;
        final upload = recurringPatternToUpload(pattern);
        final id = _observationId(
          ownerUserId: ownerUserId,
          pattern: pattern,
          lastSeenMs: lastSeenMs,
        );
        await _db.customStatement(
          '''
INSERT OR IGNORE INTO recurring_pattern_observations (
  id,
  owner_user_id,
  merchant_key,
  cadence,
  currency,
  median_amount_minor,
  occurrences,
  occurrence_ids_json,
  last_seen_at,
  observed_at,
  payload_json
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
          [
            id,
            ownerUserId,
            pattern.merchantKey,
            pattern.cadence.name,
            pattern.currency.toUpperCase(),
            pattern.medianAmountMinor,
            pattern.occurrenceIds.length,
            jsonEncode(pattern.occurrenceIds),
            lastSeenMs,
            observedAtMs,
            jsonEncode(upload.payload),
          ],
        );
      }
    });
  }

  Future<List<RecurringPatternObservation>> readObservations({
    required String ownerUserId,
  }) async {
    final rows = await _db
        .customSelect(
          '''
SELECT
  merchant_key,
  cadence,
  currency,
  median_amount_minor,
  occurrences,
  last_seen_at,
  observed_at
FROM recurring_pattern_observations
WHERE owner_user_id = ?
ORDER BY merchant_key, currency, cadence, last_seen_at, observed_at
''',
          variables: [Variable.withString(ownerUserId)],
          readsFrom: const {},
        )
        .get();
    return [
      for (final row in rows)
        RecurringPatternObservation(
          merchantKey: row.read<String>('merchant_key'),
          cadence: _cadence(row.read<String>('cadence')),
          currency: row.read<String>('currency'),
          medianAmountMinor: row.read<int>('median_amount_minor'),
          occurrences: row.read<int>('occurrences'),
          lastSeenAt: _utcMillis(row.read<int>('last_seen_at')),
          observedAt: _utcMillis(row.read<int>('observed_at')),
        ),
    ];
  }

  Future<List<SubscriptionChange>> detectHistoricalChanges({
    required String ownerUserId,
  }) async {
    final observations = await readObservations(ownerUserId: ownerUserId);
    return detectSubscriptionChangesFromPatternHistory(observations);
  }

  static String _observationId({
    required String ownerUserId,
    required RecurringPattern pattern,
    required int lastSeenMs,
  }) {
    return [
      ownerUserId,
      pattern.merchantKey,
      pattern.currency.toUpperCase(),
      pattern.cadence.name,
      lastSeenMs,
      pattern.medianAmountMinor,
    ].join('|');
  }

  static RecurringCadence _cadence(String value) {
    return RecurringCadence.values.firstWhere(
      (cadence) => cadence.name == value,
      orElse: () => RecurringCadence.monthly,
    );
  }

  static DateTime _utcMillis(int millis) {
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
}
