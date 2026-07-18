import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_evidence_navigation_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'stores only bounded privacy-safe outcomes and summarizes a window',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesAgentEvidenceNavigationStore(preferences);
      final now = DateTime.utc(2026, 7, 19);

      await store.record(
        occurredAt: now.subtract(const Duration(days: 31)),
        succeeded: false,
      );
      await store.record(
        occurredAt: now.subtract(const Duration(days: 2)),
        succeeded: true,
      );
      await store.record(
        occurredAt: now.subtract(const Duration(days: 1)),
        succeeded: false,
      );

      final summary = await store.summarize(
        since: now.subtract(const Duration(days: 30)),
      );
      expect(summary.attempts, 2);
      expect(summary.successes, 1);
      expect(summary.successRate, 0.5);

      final key = preferences.getKeys().single;
      final encoded = preferences.getString(key)!;
      final events = jsonDecode(encoded) as List<Object?>;
      expect(events, hasLength(3));
      expect(encoded, isNot(contains('/evidence')));
      expect(encoded, isNot(contains('artifact')));
      expect((events.first! as Map<String, Object?>).keys, <String>{
        'at',
        'succeeded',
      });
    },
  );

  test(
    'serializes concurrent writes and keeps the newest 200 events',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesAgentEvidenceNavigationStore(preferences);
      final start = DateTime.utc(2026, 7, 1);

      await Future.wait(<Future<void>>[
        for (var i = 0; i < 205; i++)
          store.record(
            occurredAt: start.add(Duration(minutes: i)),
            succeeded: i.isEven,
          ),
      ]);

      final summary = await store.summarize(since: start);
      expect(summary.attempts, 200);
      expect(summary.successes, 100);
    },
  );

  test('ignores malformed persisted history', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'naviwealth.agent.evidence_navigation.v1': '{not-json',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesAgentEvidenceNavigationStore(preferences);

    final summary = await store.summarize(since: DateTime.utc(2026));

    expect(summary.attempts, 0);
    expect(summary.successes, 0);
  });
}
