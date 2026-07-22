import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_preference_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/health/agents/briefing_synthesizer.dart';
import 'package:naviwealth/features/health/agents/morning_briefing_agent.dart';
import 'package:naviwealth/features/health/data/health_metric_memory_indexer.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
  return _runtimeForDb(db);
}

MemoryRuntime _runtimeForDb(AppDatabase db, {DateTime Function()? clock}) {
  return MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
    clock: clock,
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
      final failures = evaluateAgentOutcomeCase(
        regressionCase: agentOutcomeRegressionCaseById(
          'health.morning_briefing.no_finding',
        ),
        result: out,
      );
      expect(failures, isEmpty, reason: failures.join('\n'));
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

    test(
      'persists a unified briefing artifact when a store is provided',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final rt = _runtimeForDb(db);
        final store = SqliteAgentArtifactStore(db: db);

        final out = await MorningBriefingAgent.synthesize(
          events: [
            _sleepEvent(
              id: 'h1',
              at: yesterdayEvening,
              seconds: 4.5 * 3600.0,
              extraEntities: {'short_sleep'},
            ),
            _hrvEvent(id: 'h2', at: yesterdayEvening, ms: 44),
            _financeEvent(id: 'f1', at: yesterdayEvening, type: 'trade_opened'),
          ],
          ownerUserId: 'u',
          startedAt: now,
          finishedAt: now.add(const Duration(milliseconds: 50)),
          runtime: rt,
          artifactStore: store,
        );

        expect(out.status, AgentRunStatus.completed);
        expect(out.artifactId, '$kMorningBriefingAgentId:2026-05-27');

        final artifact = await store.read(out.artifactId!);
        expect(artifact, isNotNull);
        expect(artifact!.kind, AgentArtifactKind.briefing);
        expect(artifact.domain, 'health');
        expect(artifact.severity, AgentArtifactSeverity.attention);
        expect(artifact.memoryId, out.memoryId);
        expect(artifact.summary, out.summary);
        expect(
          artifact.insights.map((insight) => insight.title),
          containsAll(['Sleep', 'HRV', 'Finance']),
        );
        expect(
          artifact.evidence.map((evidence) => evidence.id),
          contains('h1'),
        );
        expect(
          artifact.evidence.map((evidence) => evidence.id),
          contains('f1'),
        );
        expect(artifact.actions.single.kind, 'review');
        final outcomeFailures = evaluateAgentOutcomeCase(
          regressionCase: agentOutcomeRegressionCaseById(
            'health.morning_briefing.ready',
          ),
          result: out,
          artifact: artifact,
        );
        expect(outcomeFailures, isEmpty);
      },
    );

    test('programmatic briefing uses Chinese locale when requested', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final rt = _runtimeForDb(db);
      final store = SqliteAgentArtifactStore(db: db);
      final l10n = lookupAppLocalizations(const Locale('zh'));

      final out = await MorningBriefingAgent.synthesize(
        events: [
          _sleepEvent(id: 'h1', at: yesterdayEvening, seconds: 7.5 * 3600.0),
          _hrvEvent(id: 'h2', at: yesterdayEvening, ms: 52),
        ],
        ownerUserId: 'u',
        startedAt: now,
        finishedAt: now.add(const Duration(milliseconds: 50)),
        runtime: rt,
        artifactStore: store,
        l10n: l10n,
      );

      expect(out.status, AgentRunStatus.completed);
      expect(out.summary, contains('睡眠 7.5 小时'));
      expect(out.summary, contains('HRV 52 ms'));

      final artifact = await store.read(out.artifactId!);
      expect(artifact?.title, '晨间简报');
      expect(
        artifact?.insights.map((insight) => insight.title),
        containsAll(['睡眠', 'HRV']),
      );
      expect(artifact?.actions.single.label, '查看简报');
    });

    test(
      'persists synthesizer trace id onto result, artifact, and memory',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final rt = _runtimeForDb(db);
        final store = SqliteAgentArtifactStore(db: db);

        final out = await MorningBriefingAgent.synthesize(
          events: [
            _sleepEvent(id: 'h1', at: yesterdayEvening, seconds: 7.5 * 3600.0),
          ],
          ownerUserId: 'u',
          startedAt: now,
          finishedAt: now.add(const Duration(milliseconds: 50)),
          runtime: rt,
          synthesizer: const _TraceBriefingSynthesizer(),
          artifactStore: store,
        );

        expect(out.status, AgentRunStatus.completed);
        expect(out.traceId, 'trace-health-1');

        final artifact = await store.read(out.artifactId!);
        expect(artifact?.traceId, 'trace-health-1');

        final memories = await rt.recall(
          ownerUserId: 'u',
          entityFilter: const {'morning_briefing'},
          validAt: now,
          topK: 1,
        );
        expect(memories.single.record.payload['trace_id'], 'trace-health-1');
        final outcome = memories.single.record.payload['outcome'] as Map;
        expect(outcome['trace_id'], 'trace-health-1');
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

  test(
    'run skips local notification when agent notifications are off',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final rt = _runtimeForDb(db, clock: () => now);
      await rt.recordEvent(
        _sleepEvent(id: 'h1', at: yesterdayEvening, seconds: 7.5 * 3600.0),
      );
      final store = SqliteAgentArtifactStore(db: db);
      final preferences = InMemoryAgentPreferenceStore();
      await preferences.setNotificationsEnabled(
        ownerUserId: 'u',
        agentId: kMorningBriefingAgentId,
        enabled: false,
        updatedAt: now,
      );
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => 'u'),
          memoryRuntimeProvider.overrideWith((ref) async => rt),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => store,
          ),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferences,
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = _RecordingNotificationService();

      final result = await MorningBriefingAgent(
        notifier: notifier,
      ).run(AgentContext(ref: container.read(_refProvider), now: now));

      expect(result.status, AgentRunStatus.completed);
      expect(await store.read(result.artifactId!), isNotNull);
      expect(notifier.showCount, 0);
    },
  );

  test('run notification deep-links to the persisted artifact', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final rt = _runtimeForDb(db, clock: () => now);
    await rt.recordEvent(
      _sleepEvent(id: 'h1', at: yesterdayEvening, seconds: 7.5 * 3600.0),
    );
    final store = SqliteAgentArtifactStore(db: db);
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(() async => 'u'),
        memoryRuntimeProvider.overrideWith((ref) async => rt),
        agent_providers.agentArtifactStoreProvider.overrideWith(
          (ref) async => store,
        ),
        agent_providers.agentPreferenceStoreProvider.overrideWith(
          (ref) async => InMemoryAgentPreferenceStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = _RecordingNotificationService();

    final result = await MorningBriefingAgent(
      notifier: notifier,
    ).run(AgentContext(ref: container.read(_refProvider), now: now));

    expect(result.status, AgentRunStatus.completed);
    expect(notifier.showCount, 1);
    expect(
      notifier.lastPayload,
      '/insights/${Uri.encodeComponent(result.artifactId!)}',
    );
  });
}

final _refProvider = Provider<Ref>((ref) => ref);

class _TraceBriefingSynthesizer implements BriefingSynthesizer {
  const _TraceBriefingSynthesizer();

  @override
  Future<BriefingOutput> synthesize(BriefingInputs inputs) async {
    return const BriefingOutput(
      summary: 'LLM briefing with trace.',
      sleepLine: 'Slept 7.5h',
      source: BriefingSource.llm,
      traceId: 'trace-health-1',
    );
  }
}

class _RecordingNotificationService implements NotificationService {
  int showCount = 0;
  String? lastPayload;

  @override
  Stream<String> get payloads => const Stream<String>.empty();

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<String?> initialPayload() async => null;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required NotificationChannelSpec channel,
    String? payload,
  }) async {
    showCount += 1;
    lastPayload = payload;
  }
}
