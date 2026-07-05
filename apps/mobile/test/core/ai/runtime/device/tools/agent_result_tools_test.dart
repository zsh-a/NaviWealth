import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/agent_result_tools.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';

import '../../../../persistence/test_database.dart';

const _owner = 'agent-tool-user';

Future<T> _withRef<T>(
  ProviderContainer container,
  Future<T> Function(Ref ref) body,
) {
  final probe = FutureProvider<T>((ref) => body(ref));
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}

DeviceToolContext _ctx(Ref ref) {
  return DeviceToolContext(ref: ref, session: const DeviceToolSession());
}

ProviderContainer _container(AppDatabase db) {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((ref) async => db),
      currentUserIdProvider.overrideWithValue(() async => _owner),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = makeTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  test('get_agent_artifacts reads one artifact by id', () async {
    final store = SqliteAgentArtifactStore(db: db);
    await store.save(
      AgentArtifact(
        id: 'weekly_wealth_review:2026-07-05',
        ownerUserId: _owner,
        agentId: 'weekly_wealth_review',
        domain: 'finance',
        kind: AgentArtifactKind.review,
        severity: AgentArtifactSeverity.attention,
        title: 'Weekly Wealth Review',
        summary: 'Net worth changed.',
        insights: const <AgentInsight>[
          AgentInsight(title: 'Net worth', body: 'Net worth changed.'),
        ],
        evidence: const <AgentEvidenceRef>[
          AgentEvidenceRef(type: 'finance_holding', id: 'holding-1'),
        ],
        actions: const <AgentAction>[
          AgentAction(kind: 'review', label: 'Review wealth'),
        ],
        memoryId: 'memory-1',
        traceId: 'trace-1',
        createdAt: DateTime.utc(2026, 7, 5),
      ),
    );
    final container = _container(db);

    final output = await _withRef(
      container,
      (ref) => const GetAgentArtifactsTool().invoke(_ctx(ref), {
        'artifact_id': 'weekly_wealth_review:2026-07-05',
      }),
    );

    final json = output! as Map<String, Object?>;
    final artifacts = json['artifacts']! as List<Object?>;
    final artifact = artifacts.single! as Map<String, Object?>;
    expect(artifact['id'], 'weekly_wealth_review:2026-07-05');
    expect(artifact['kind'], 'review');
    expect(artifact['severity'], 'attention');
    expect(artifact['trace_id'], 'trace-1');
    expect(artifact['memory_id'], 'memory-1');
    final evidence = artifact['evidence']! as List<Object?>;
    expect(
      (evidence.single! as Map<String, Object?>)['type'],
      'finance_holding',
    );
  });

  test('get_agent_runs reads latest run by agent id', () async {
    final runStore = SqliteAgentRunStore(db: db);
    const agent = _FakeAgent();
    final startedAt = DateTime.utc(2026, 7, 5, 9);
    await runStore.finishRun(
      ownerUserId: _owner,
      agent: agent,
      runStartedAt: startedAt,
      trigger: AgentRunTrigger.manual,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(seconds: 3)),
        summary: 'Ready result',
        memoryId: 'memory-1',
        artifactId: 'artifact-1',
        traceId: 'trace-1',
      ),
    );
    final container = _container(db);

    final output = await _withRef(
      container,
      (ref) =>
          const GetAgentRunsTool().invoke(_ctx(ref), {'agent_id': agent.id}),
    );

    final json = output! as Map<String, Object?>;
    final runs = json['runs']! as List<Object?>;
    final run = runs.single! as Map<String, Object?>;
    expect(run['agent_id'], agent.id);
    expect(run['status'], 'ready');
    expect(run['trigger'], 'manual');
    expect(run['artifact_id'], 'artifact-1');
    expect(run['trace_id'], 'trace-1');
  });

  test('tools return invalid input errors instead of throwing', () async {
    final container = _container(db);

    final artifacts = await _withRef(
      container,
      (ref) => const GetAgentArtifactsTool().invoke(_ctx(ref), const {}),
    );
    final runs = await _withRef(
      container,
      (ref) => const GetAgentRunsTool().invoke(_ctx(ref), const {}),
    );

    expect((artifacts! as Map<String, Object?>)['code'], 'invalid_input');
    expect((runs! as Map<String, Object?>)['code'], 'invalid_input');
  });
}

class _FakeAgent implements Agent {
  const _FakeAgent();

  @override
  String get id => 'weekly_wealth_review';

  @override
  String get name => 'Weekly Wealth Review';

  @override
  AgentSchedule get schedule => AgentSchedule.everyHours(24);

  @override
  Future<AgentRunResult> run(AgentContext ctx) {
    throw UnimplementedError();
  }
}
