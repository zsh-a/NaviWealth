import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/skills/skills.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/expense/data/recurring_pattern_history_store.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  late AppDatabase db;
  late RecurringPatternHistoryStore store;

  setUp(() {
    db = makeTestDatabase();
    store = RecurringPatternHistoryStore(db);
  });

  tearDown(() => db.close());

  RecurringPattern pattern({
    required int median,
    required DateTime lastSeenAt,
    List<String> occurrenceIds = const ['a', 'b', 'c'],
  }) {
    return RecurringPattern(
      merchantKey: 'netflix',
      cadence: RecurringCadence.monthly,
      medianAmountMinor: median,
      currency: 'usd',
      occurrenceIds: occurrenceIds,
      lastSeenAt: lastSeenAt,
    );
  }

  Future<int> observationCount() async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS count FROM recurring_pattern_observations',
        )
        .getSingle();
    return row.read<int>('count');
  }

  test('recordPatterns creates idempotent local observations', () async {
    final p = pattern(median: -1099, lastSeenAt: DateTime.utc(2026, 3, 1));

    await store.recordPatterns(
      ownerUserId: 'u1',
      observedAt: DateTime.utc(2026, 3, 2),
      patterns: [p],
    );
    await store.recordPatterns(
      ownerUserId: 'u1',
      observedAt: DateTime.utc(2026, 3, 3),
      patterns: [p],
    );

    expect(await observationCount(), 1);
    final observations = await store.readObservations(ownerUserId: 'u1');
    expect(observations, hasLength(1));
    expect(observations.single.currency, 'USD');
    expect(observations.single.medianAmountMinor, -1099);
    expect(observations.single.occurrences, 3);
  });

  test(
    'detectHistoricalChanges compares stable prices across sessions',
    () async {
      await store.recordPatterns(
        ownerUserId: 'u1',
        observedAt: DateTime.utc(2026, 3, 2),
        patterns: [
          pattern(
            median: -1099,
            lastSeenAt: DateTime.utc(2026, 3, 1),
            occurrenceIds: const ['jan', 'feb', 'mar'],
          ),
        ],
      );
      await store.recordPatterns(
        ownerUserId: 'u1',
        observedAt: DateTime.utc(2026, 6, 2),
        patterns: [
          pattern(
            median: -1299,
            lastSeenAt: DateTime.utc(2026, 6, 1),
            occurrenceIds: const ['apr', 'may', 'jun'],
          ),
        ],
      );

      final changes = await store.detectHistoricalChanges(ownerUserId: 'u1');

      expect(changes, hasLength(1));
      final change = changes.single;
      expect(change.merchantKey, 'netflix');
      expect(change.currency, 'USD');
      expect(change.prevMedianAmountMinor, -1099);
      expect(change.newMedianAmountMinor, -1299);
      expect(change.deltaRatio, closeTo(-200 / 1099, 0.0001));
      expect(change.since, DateTime.utc(2026, 6, 1));
    },
  );

  test('detectHistoricalChanges is scoped by owner', () async {
    await store.recordPatterns(
      ownerUserId: 'u1',
      observedAt: DateTime.utc(2026, 3, 2),
      patterns: [pattern(median: -1099, lastSeenAt: DateTime.utc(2026, 3, 1))],
    );
    await store.recordPatterns(
      ownerUserId: 'u2',
      observedAt: DateTime.utc(2026, 6, 2),
      patterns: [pattern(median: -1299, lastSeenAt: DateTime.utc(2026, 6, 1))],
    );

    expect(await store.detectHistoricalChanges(ownerUserId: 'u1'), isEmpty);
    expect(await store.detectHistoricalChanges(ownerUserId: 'u2'), isEmpty);
  });
}
