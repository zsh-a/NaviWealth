import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_finding_store.dart';

import '../../persistence/test_database.dart';

void main() {
  test(
    'reconcile keeps stable findings and resolves disappeared findings',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentFindingStore(db: db);
      final firstSeen = DateTime.utc(2026, 7, 1);
      AgentFinding finding(String detail) => AgentFinding(
        id: 'finding-1',
        ownerUserId: 'owner',
        agentId: 'agent',
        domain: 'knowledge',
        kind: 'contradiction',
        severity: AgentArtifactSeverity.warning,
        confidence: 0.9,
        payload: <String, Object?>{'detail': detail},
      );

      final first = await store.reconcile(
        ownerUserId: 'owner',
        agentId: 'agent',
        findings: <AgentFinding>[finding('first')],
        observedAt: firstSeen,
      );
      expect(first.changedIds, {'finding-1'});

      final unchanged = await store.reconcile(
        ownerUserId: 'owner',
        agentId: 'agent',
        findings: <AgentFinding>[finding('first')],
        observedAt: firstSeen.add(const Duration(hours: 1)),
      );
      expect(unchanged.changedIds, isEmpty);
      expect(await store.listOpen(ownerUserId: 'owner'), hasLength(1));

      final changed = await store.reconcile(
        ownerUserId: 'owner',
        agentId: 'agent',
        findings: <AgentFinding>[finding('updated')],
        observedAt: firstSeen.add(const Duration(hours: 2)),
      );
      expect(changed.changedIds, {'finding-1'});

      await store.ignore(
        ownerUserId: 'owner',
        id: 'finding-1',
        at: firstSeen.add(const Duration(hours: 2, minutes: 1)),
      );
      final ignored = await store.reconcile(
        ownerUserId: 'owner',
        agentId: 'agent',
        findings: <AgentFinding>[finding('updated')],
        observedAt: firstSeen.add(const Duration(hours: 2, minutes: 2)),
      );
      expect(ignored.changedIds, isEmpty);
      expect(ignored.openIds, isEmpty);
      expect(await store.listOpen(ownerUserId: 'owner'), isEmpty);

      final reopened = await store.reconcile(
        ownerUserId: 'owner',
        agentId: 'agent',
        findings: <AgentFinding>[finding('reopened evidence')],
        observedAt: firstSeen.add(const Duration(hours: 2, minutes: 3)),
      );
      expect(reopened.changedIds, {'finding-1'});

      final resolved = await store.reconcile(
        ownerUserId: 'owner',
        agentId: 'agent',
        findings: const <AgentFinding>[],
        observedAt: firstSeen.add(const Duration(hours: 3)),
      );
      expect(resolved.resolvedIds, {'finding-1'});
      expect(await store.listOpen(ownerUserId: 'owner'), isEmpty);
    },
  );
}
