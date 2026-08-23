import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_feedback_store.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  test('records feedback with causal fingerprints outside Memory', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentFeedbackStore(db: db);
    final artifact = AgentArtifact(
      id: 'daily:one',
      ownerUserId: 'u1',
      agentId: 'daily_navigator',
      domain: 'life',
      kind: AgentArtifactKind.briefing,
      severity: AgentArtifactSeverity.attention,
      title: 'Today',
      summary: 'Recover first.',
      actions: const <AgentAction>[
        AgentAction(
          kind: 'review',
          label: 'Review recovery',
          route: '/health',
          payload: <String, Object?>{
            'life_context_fingerprint': 'context-1',
            'finding_fingerprint': 'finding-1',
            'attention_decision_id': 'attention-1',
          },
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 23),
    );

    await store.record(
      artifact: artifact,
      kind: AgentFeedbackKind.accepted,
      action: artifact.actions.single,
      at: DateTime.utc(2026, 8, 23, 8),
    );
    await store.record(
      artifact: artifact,
      kind: AgentFeedbackKind.completed,
      payload: const <String, Object?>{'outcome': 'recovery_day'},
      at: DateTime.utc(2026, 8, 23, 18),
    );

    final feedback = await store.listForArtifact(
      ownerUserId: 'u1',
      artifactId: artifact.id,
    );
    expect(feedback.map((item) => item.kind), <AgentFeedbackKind>[
      AgentFeedbackKind.accepted,
      AgentFeedbackKind.completed,
    ]);
    expect(feedback.first.lifeContextFingerprint, 'context-1');
    expect(feedback.first.findingFingerprint, 'finding-1');
    expect(feedback.first.attentionDecisionId, 'attention-1');
    expect(feedback.first.actionKind, 'review');
    expect(feedback.last.payload['outcome'], 'recovery_day');

    final memories = await db
        .customSelect('SELECT COUNT(*) AS count FROM memories')
        .getSingle();
    expect(memories.read<int>('count'), 0);
  });
}
