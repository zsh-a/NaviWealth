import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_routes.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/features/life/data/life_events_provider.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';

void main() {
  test('Agent result Life event preserves artifact identity in its route', () {
    final artifact = AgentArtifact(
      id: 'artifact/with spaces',
      ownerUserId: 'user-1',
      agentId: 'weekly_wealth_review',
      domain: DomainScope.finance.wire,
      kind: AgentArtifactKind.review,
      severity: AgentArtifactSeverity.attention,
      title: '  Weekly conclusion  ',
      summary: 'Review summary',
      createdAt: DateTime.utc(2026, 7, 22),
    );

    final event = lifeEventForAgentArtifact(artifact);

    expect(event.domain, DomainScope.finance);
    expect(event.template, LifeEventTemplate.agentResult);
    expect(event.params, const ['Weekly conclusion']);
    expect(event.routePath, AgentArtifactRoutes.detail(artifact.id));
    expect(event.routePath, '/insights/artifact%2Fwith%20spaces');
    expect(event.actionSuggestion?.sourceRowId, artifact.id);
    expect(
      event.actionSuggestion?.template,
      LifeActionTemplate.reviewAgentInsight,
    );
  });

  test('rejects artifacts outside registered LifeOS domains', () {
    final artifact = AgentArtifact(
      id: 'artifact-1',
      ownerUserId: 'user-1',
      agentId: 'unknown',
      domain: 'future-domain',
      kind: AgentArtifactKind.review,
      severity: AgentArtifactSeverity.info,
      title: 'Conclusion',
      summary: 'Summary',
      createdAt: DateTime.utc(2026, 7, 22),
    );

    expect(() => lifeEventForAgentArtifact(artifact), throwsArgumentError);
  });
}
