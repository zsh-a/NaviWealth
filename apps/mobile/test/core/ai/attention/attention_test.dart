import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/attention/attention.dart';
import 'package:naviwealth/core/ai/attention/attention_store.dart';

import '../../persistence/test_database.dart';

final _now = DateTime.utc(2026, 8, 23, 8);

AttentionCandidate _candidate(
  String fingerprint, {
  AgentArtifactSeverity severity = AgentArtifactSeverity.warning,
}) => AttentionCandidate(
  id: 'candidate-$fingerprint',
  agentId: 'daily_navigator',
  findingFingerprint: fingerprint,
  severity: severity,
  confidence: 0.9,
  actionable: true,
  fresh: true,
  evidenceComplete: true,
  observedAt: _now,
);

void main() {
  test('unchanged and suppressed findings stay silent', () {
    const arbiter = AttentionArbiter();
    final unchanged = arbiter.decide(
      ownerUserId: 'owner',
      candidate: _candidate('unchanged'),
      context: const AttentionPolicyContext(
        novel: false,
        suppressed: false,
        notificationsAllowed: true,
        recentInterruptCount: 0,
      ),
      decidedAt: _now,
    );
    final suppressed = arbiter.decide(
      ownerUserId: 'owner',
      candidate: _candidate('suppressed'),
      context: const AttentionPolicyContext(
        novel: true,
        suppressed: true,
        notificationsAllowed: true,
        recentInterruptCount: 0,
      ),
      decidedAt: _now,
    );

    expect(unchanged.level, AttentionLevel.silent);
    expect(unchanged.reasons, contains('unchanged_finding'));
    expect(suppressed.level, AttentionLevel.silent);
    expect(suppressed.reasons, contains('finding_suppressed'));
  });

  test('persists decisions and enforces the global interrupt budget', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAttentionDecisionStore(db: db);
    final service = AttentionDecisionService(store: store);

    for (var index = 0; index < 3; index += 1) {
      final decision = await service.evaluate(
        ownerUserId: 'owner',
        candidate: _candidate('warning-$index'),
        novel: true,
        suppressed: false,
        notificationsAllowed: true,
        decidedAt: _now.add(Duration(minutes: index)),
      );
      expect(decision.level, AttentionLevel.interrupt);
    }
    final overBudget = await service.evaluate(
      ownerUserId: 'owner',
      candidate: _candidate('warning-4'),
      novel: true,
      suppressed: false,
      notificationsAllowed: true,
      decidedAt: _now.add(const Duration(minutes: 4)),
    );

    expect(overBudget.level, AttentionLevel.surface);
    expect(overBudget.reasons, contains('interrupt_budget_exhausted'));
    expect(await store.listRecent(ownerUserId: 'owner'), hasLength(4));
  });
}
