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
    expect(saved?.dismissedAt, isNull);
    expect(saved?.snoozedUntil, isNull);
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

  test(
    'SqliteAgentArtifactStore hides dismissed snoozed and expired artifacts',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentArtifactStore(db: db);
      final now = DateTime.utc(2026, 7, 5, 12);

      Future<void> save({
        required String id,
        int minutesAgo = 1,
        DateTime? expiresAt,
      }) {
        return store.save(
          AgentArtifact(
            id: id,
            ownerUserId: 'user-1',
            agentId: 'weekly_summary',
            domain: 'health',
            kind: AgentArtifactKind.review,
            severity: AgentArtifactSeverity.info,
            title: id,
            summary: id,
            createdAt: now.subtract(Duration(minutes: minutesAgo)),
            expiresAt: expiresAt,
          ),
        );
      }

      await save(id: 'visible', minutesAgo: 4);
      await save(id: 'dismissed', minutesAgo: 3);
      await save(id: 'snoozed', minutesAgo: 2);
      await save(
        id: 'expired',
        minutesAgo: 1,
        expiresAt: now.subtract(const Duration(days: 1)),
      );

      await store.dismiss(
        ownerUserId: 'user-1',
        id: 'dismissed',
        dismissedAt: now,
      );
      await store.snooze(
        ownerUserId: 'user-1',
        id: 'snoozed',
        until: now.add(const Duration(hours: 2)),
      );

      final latest = await store.latestForAgent(
        ownerUserId: 'user-1',
        agentId: 'weekly_summary',
        visibleAt: now,
      );
      expect(latest.map((artifact) => artifact.id), ['visible']);

      final dismissed = await store.read('dismissed');
      final snoozed = await store.read('snoozed');
      expect(dismissed?.dismissedAt, now);
      expect(dismissed?.isVisibleAt(now), isFalse);
      expect(snoozed?.snoozedUntil, now.add(const Duration(hours: 2)));
      expect(snoozed?.isVisibleAt(now), isFalse);

      final afterSnooze = await store.latestForDomain(
        ownerUserId: 'user-1',
        domain: 'health',
        visibleAt: now.add(const Duration(hours: 3)),
      );
      expect(afterSnooze.map((artifact) => artifact.id), [
        'snoozed',
        'visible',
      ]);
    },
  );

  test(
    'SqliteAgentArtifactStore preserves local visibility state across upserts',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentArtifactStore(db: db);
      final now = DateTime.utc(2026, 7, 5, 12);

      AgentArtifact artifact({required String summary}) {
        return AgentArtifact(
          id: 'stable-agent-artifact',
          ownerUserId: 'user-1',
          agentId: 'weekly_summary',
          domain: 'health',
          kind: AgentArtifactKind.review,
          severity: AgentArtifactSeverity.info,
          title: 'Weekly summary',
          summary: summary,
          createdAt: now,
        );
      }

      await store.save(artifact(summary: 'first result'));
      await store.dismiss(
        ownerUserId: 'user-1',
        id: 'stable-agent-artifact',
        dismissedAt: now.add(const Duration(minutes: 1)),
      );

      await store.save(artifact(summary: 'updated result'));

      final dismissed = await store.read('stable-agent-artifact');
      expect(dismissed?.summary, 'updated result');
      expect(dismissed?.dismissedAt, now.add(const Duration(minutes: 1)));
      expect(
        await store.latestForAgent(
          ownerUserId: 'user-1',
          agentId: 'weekly_summary',
          visibleAt: now.add(const Duration(minutes: 2)),
        ),
        isEmpty,
      );

      final snoozedUntil = now.add(const Duration(hours: 3));
      await store.save(
        AgentArtifact(
          id: 'stable-snoozed-artifact',
          ownerUserId: 'user-1',
          agentId: 'weekly_summary',
          domain: 'health',
          kind: AgentArtifactKind.review,
          severity: AgentArtifactSeverity.info,
          title: 'Weekly summary',
          summary: 'first snoozed result',
          createdAt: now,
        ),
      );
      await store.snooze(
        ownerUserId: 'user-1',
        id: 'stable-snoozed-artifact',
        until: snoozedUntil,
      );
      await store.save(
        AgentArtifact(
          id: 'stable-snoozed-artifact',
          ownerUserId: 'user-1',
          agentId: 'weekly_summary',
          domain: 'health',
          kind: AgentArtifactKind.review,
          severity: AgentArtifactSeverity.warning,
          title: 'Weekly summary',
          summary: 'updated snoozed result',
          createdAt: now.add(const Duration(minutes: 5)),
        ),
      );

      final snoozed = await store.read('stable-snoozed-artifact');
      expect(snoozed?.summary, 'updated snoozed result');
      expect(snoozed?.severity, AgentArtifactSeverity.warning);
      expect(snoozed?.snoozedUntil, snoozedUntil);
      expect(
        await store.latestForAgent(
          ownerUserId: 'user-1',
          agentId: 'weekly_summary',
          visibleAt: now.add(const Duration(hours: 1)),
        ),
        isEmpty,
      );
      expect(
        (await store.latestForAgent(
          ownerUserId: 'user-1',
          agentId: 'weekly_summary',
          visibleAt: now.add(const Duration(hours: 4)),
        )).map((artifact) => artifact.id),
        ['stable-snoozed-artifact'],
      );
    },
  );

  test(
    'SqliteAgentArtifactStore resets visibility state when artifact owner changes',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentArtifactStore(db: db);
      final now = DateTime.utc(2026, 7, 5, 12);

      AgentArtifact artifact({
        required String ownerUserId,
        required String summary,
      }) {
        return AgentArtifact(
          id: 'stable-agent-artifact',
          ownerUserId: ownerUserId,
          agentId: 'weekly_summary',
          domain: 'health',
          kind: AgentArtifactKind.review,
          severity: AgentArtifactSeverity.info,
          title: 'Weekly summary',
          summary: summary,
          createdAt: now,
        );
      }

      await store.save(
        artifact(ownerUserId: 'user-1', summary: 'first user result'),
      );
      await store.dismiss(
        ownerUserId: 'user-1',
        id: 'stable-agent-artifact',
        dismissedAt: now.add(const Duration(minutes: 1)),
      );

      await store.save(
        artifact(ownerUserId: 'user-2', summary: 'second user result'),
      );

      final saved = await store.read('stable-agent-artifact');
      expect(saved?.ownerUserId, 'user-2');
      expect(saved?.summary, 'second user result');
      expect(saved?.dismissedAt, isNull);
      expect(saved?.snoozedUntil, isNull);
      expect(
        (await store.latestForAgent(
          ownerUserId: 'user-2',
          agentId: 'weekly_summary',
          visibleAt: now.add(const Duration(minutes: 2)),
        )).map((artifact) => artifact.id),
        ['stable-agent-artifact'],
      );
    },
  );
}
