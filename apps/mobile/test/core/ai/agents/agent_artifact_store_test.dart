import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  test('SqliteAgentArtifactStore saves and reads a full artifact', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentArtifactStore(db: db);
    final createdAt = DateTime.utc(2026, 7, 5, 8);
    final artifact = AgentArtifact(
      id: 'artifact-1',
      ownerUserId: 'user-1',
      agentId: 'morning_briefing',
      domain: 'health',
      kind: AgentArtifactKind.briefing,
      severity: AgentArtifactSeverity.attention,
      title: 'Morning briefing',
      summary: 'Recovery is mixed.',
      insights: const [
        AgentInsight(
          title: 'Sleep debt',
          body: 'Sleep was below target for two nights.',
          severity: AgentArtifactSeverity.warning,
          payload: <String, Object?>{'sleep_hours': 5.8},
        ),
      ],
      evidence: const [
        AgentEvidenceRef(
          type: 'health_metric',
          id: 'sleep:2026-07-05',
          label: 'Sleep',
          route: '/health/trend',
        ),
      ],
      actions: const [
        AgentAction(
          kind: 'follow_up',
          label: 'Explain recovery',
          intent: 'health.explainRecoveryAlert',
          objectType: 'agent_artifact',
          objectId: 'artifact-1',
        ),
      ],
      memoryId: 'memory-1',
      traceId: 'trace-1',
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(days: 7)),
    );

    await store.save(artifact);

    final saved = await store.read('artifact-1');
    expect(saved?.kind, AgentArtifactKind.briefing);
    expect(saved?.severity, AgentArtifactSeverity.attention);
    expect(saved?.insights.single.payload['sleep_hours'], 5.8);
    expect(saved?.evidence.single.route, '/health/trend');
    expect(saved?.actions.single.intent, 'health.explainRecoveryAlert');
    expect(saved?.memoryId, 'memory-1');
    expect(saved?.traceId, 'trace-1');
  });

  test(
    'SqliteAgentArtifactStore scopes latest reads by agent and domain',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentArtifactStore(db: db);

      Future<void> save({
        required String id,
        required String agentId,
        required String domain,
        required DateTime createdAt,
      }) {
        return store.save(
          AgentArtifact(
            id: id,
            ownerUserId: 'user-1',
            agentId: agentId,
            domain: domain,
            kind: AgentArtifactKind.review,
            severity: AgentArtifactSeverity.info,
            title: id,
            summary: id,
            createdAt: createdAt,
          ),
        );
      }

      await save(
        id: 'old-health',
        agentId: 'weekly_summary',
        domain: 'health',
        createdAt: DateTime.utc(2026, 7, 1),
      );
      await save(
        id: 'new-health',
        agentId: 'weekly_summary',
        domain: 'health',
        createdAt: DateTime.utc(2026, 7, 5),
      );
      await save(
        id: 'knowledge',
        agentId: 'knowledge_review',
        domain: 'knowledge',
        createdAt: DateTime.utc(2026, 7, 4),
      );

      final byAgent = await store.latestForAgent(
        ownerUserId: 'user-1',
        agentId: 'weekly_summary',
      );
      expect(byAgent.map((artifact) => artifact.id), [
        'new-health',
        'old-health',
      ]);

      final byDomain = await store.latestForDomain(
        ownerUserId: 'user-1',
        domain: 'health',
      );
      expect(byDomain.map((artifact) => artifact.id), [
        'new-health',
        'old-health',
      ]);
    },
  );
}
