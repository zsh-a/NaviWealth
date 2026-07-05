import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/features/health/agents/morning_briefing_agent.dart';
import 'package:naviwealth/features/health/data/health_metric_memory_indexer.dart';

import '../../../core/persistence/test_database.dart';

EventRecord _sleepEvent({
  required String id,
  required DateTime at,
  required double seconds,
  Set<String> extraEntities = const <String>{},
}) => EventRecord(
  id: id,
  type: kEventSleepSessionEnded,
  timestamp: at,
  source: kHealthSource,
  ownerUserId: 'u',
  summary: 'slept',
  payload: <String, Object?>{
    'kind': 'sleep_session',
    'value': seconds,
    'unit': 's',
  },
  entities: <String>{'health', 'sleep_session', ...extraEntities},
);

EventRecord _hrvEvent({
  required String id,
  required DateTime at,
  required double ms,
}) => EventRecord(
  id: id,
  type: kEventHrvRecorded,
  timestamp: at,
  source: kHealthSource,
  ownerUserId: 'u',
  summary: 'hrv',
  payload: <String, Object?>{'kind': 'hrv_daily', 'value': ms, 'unit': 'ms'},
  entities: <String>{'health', 'hrv_daily'},
);

EventRecord _financeEvent({
  required String id,
  required DateTime at,
  required String type,
}) => EventRecord(
  id: id,
  type: type,
  timestamp: at,
  source: 'options_trade_journal',
  ownerUserId: 'u',
  summary: 'trade',
  payload: const <String, Object?>{},
  entities: <String>{'NVDA'},
);

MemoryRuntime _runtime() {
  final db = makeTestDatabase();
  return MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
}

void main() {
  final now = DateTime.utc(2026, 5, 27, 7, 0);
  final yesterdayEvening = DateTime.utc(2026, 5, 26, 22);

  group('MorningBriefingAgent.synthesize', () {
    test('skips when no health events in the window', () async {
      final rt = _runtime();
      final out = await MorningBriefingAgent.synthesize(
        events: [
          _financeEvent(id: 'f1', at: yesterdayEvening, type: 'trade_opened'),
        ],
        ownerUserId: 'u',
        startedAt: now,
        finishedAt: now.add(const Duration(milliseconds: 50)),
        runtime: rt,
      );
      expect(out.status, AgentRunStatus.skipped);
      expect(out.memoryId, isNull);
    });

    test(
      'with sleep + hrv + finance events produces a multi-segment summary',
      () async {
        final rt = _runtime();
        final out = await MorningBriefingAgent.synthesize(
          events: [
            _sleepEvent(id: 'h1', at: yesterdayEvening, seconds: 7.5 * 3600.0),
            _hrvEvent(id: 'h2', at: yesterdayEvening, ms: 52),
            _financeEvent(id: 'f1', at: yesterdayEvening, type: 'trade_opened'),
            _financeEvent(id: 'f2', at: yesterdayEvening, type: 'trade_opened'),
          ],
          ownerUserId: 'u',
          startedAt: now,
          finishedAt: now.add(const Duration(milliseconds: 50)),
          runtime: rt,
        );
        expect(out.status, AgentRunStatus.completed);
        expect(out.summary, contains('Slept 7.5h'));
        expect(out.summary, contains('HRV 52ms'));
        expect(out.summary, contains('2 trade opened'));
        expect(out.memoryId, isNotNull);
        expect(out.payload['health_event_count'], 2);
        expect(out.payload['finance_event_count'], 2);
      },
    );

    test('annotates short sleep when the indexer tagged short_sleep', () async {
      final rt = _runtime();
      final out = await MorningBriefingAgent.synthesize(
        events: [
          _sleepEvent(
            id: 'h1',
            at: yesterdayEvening,
            seconds: 4.5 * 3600.0,
            extraEntities: {'short_sleep'},
          ),
        ],
        ownerUserId: 'u',
        startedAt: now,
        finishedAt: now.add(const Duration(milliseconds: 50)),
        runtime: rt,
      );
      expect(out.summary, contains('(short)'));
    });

    test(
      'memory is upserted by day key so two runs same day stay 1 record',
      () async {
        final rt = _runtime();
        Future<void> runOnceAt(DateTime at) async {
          await MorningBriefingAgent.synthesize(
            events: [
              _sleepEvent(
                id: 'h${at.hour}',
                at: at.subtract(const Duration(hours: 8)),
                seconds: 7 * 3600.0,
              ),
            ],
            ownerUserId: 'u',
            startedAt: at,
            finishedAt: at.add(const Duration(milliseconds: 50)),
            runtime: rt,
          );
        }

        await runOnceAt(now);
        await runOnceAt(now.add(const Duration(hours: 1)));
        final hits = await rt.recall(
          ownerUserId: 'u',
          entityFilter: const {'morning_briefing'},
          validAt: now.add(const Duration(hours: 2)),
          topK: 5,
        );
        expect(hits, hasLength(1));
      },
    );
  });

  test('agent advertises the contract', () {
    const agent = MorningBriefingAgent();
    expect(agent.id, 'morning_briefing');
    expect(agent.name, 'Morning Briefing');
    expect(agent.schedule.preferredHourLocal, 7);
    expect(agent.schedule.interval, const Duration(days: 1));
  });
}
