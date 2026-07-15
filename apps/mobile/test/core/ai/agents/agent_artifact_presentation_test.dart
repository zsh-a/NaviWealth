import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_presentation.dart';

void main() {
  AgentArtifact artifact({
    List<AgentMetric> metrics = const <AgentMetric>[],
    List<AgentInsight> insights = const <AgentInsight>[],
    List<AgentEvidenceRef> evidence = const <AgentEvidenceRef>[],
    List<AgentAction> actions = const <AgentAction>[],
    AgentMethodology? methodology,
  }) => AgentArtifact(
    id: 'a1',
    ownerUserId: 'u1',
    agentId: 'agent',
    domain: 'test',
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.info,
    title: 'Result',
    summary: 'Summary',
    metrics: metrics,
    insights: insights,
    evidence: evidence,
    actions: actions,
    methodology: methodology,
    createdAt: DateTime.utc(2026, 1, 1),
  );

  test('complete artifact satisfies the presentation contract', () {
    final value = artifact(
      metrics: const <AgentMetric>[AgentMetric(label: 'Metric', value: '1')],
      insights: const <AgentInsight>[
        AgentInsight(id: 'signal', title: 'Signal', body: 'Body', route: '/x'),
      ],
      evidence: const <AgentEvidenceRef>[
        AgentEvidenceRef(type: 'row', id: 'r1', route: '/x'),
      ],
      actions: const <AgentAction>[
        AgentAction(kind: 'open_route', label: 'Open', route: '/x'),
      ],
      methodology: const AgentMethodology(title: 'Method', body: 'Body'),
    );

    expect(agentArtifactPresentationIssues(value), isEmpty);
  });

  test('text-only artifact reports every missing interaction layer', () {
    final issues = agentArtifactPresentationIssues(artifact());

    expect(
      issues,
      containsAll(<String>[
        'metrics',
        'insights',
        'action.route',
        'methodology',
      ]),
    );
  });
}
