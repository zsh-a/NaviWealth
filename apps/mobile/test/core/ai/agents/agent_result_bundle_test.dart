import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart';

void main() {
  AgentArtifact artifact(
    String agentId,
    AgentArtifactSeverity severity,
    DateTime at,
  ) => AgentArtifact(
    id: 'artifact-$agentId',
    ownerUserId: 'u1',
    agentId: agentId,
    domain: 'test',
    kind: AgentArtifactKind.review,
    severity: severity,
    title: agentId,
    summary: agentId,
    createdAt: at,
  );

  AgentRunRecord run(
    String agentId,
    AgentRunLifecycleStatus status,
    DateTime at,
  ) => AgentRunRecord(
    id: 'run-$agentId',
    ownerUserId: 'u1',
    agentId: agentId,
    agentName: agentId,
    status: status,
    trigger: AgentRunTrigger.manual,
    startedAt: at,
  );

  test('pairs run state with the artifact from the same agent', () {
    final old = DateTime.utc(2026, 1, 1);
    final recent = DateTime.utc(2026, 1, 2);
    final bundle = AgentResultBundle(
      artifacts: <AgentArtifact>[
        artifact('wealth', AgentArtifactSeverity.info, old),
      ],
      latestRuns: <AgentRunRecord>[
        run('options', AgentRunLifecycleStatus.running, recent),
      ],
    );

    final wealth = bundle.entries.singleWhere(
      (entry) => entry.agentId == 'wealth',
    );
    final options = bundle.entries.singleWhere(
      (entry) => entry.agentId == 'options',
    );
    expect(wealth.runOverlay, isNull);
    expect(options.artifact, isNull);
    expect(options.runOverlay?.agentId, 'options');
    expect(
      AgentResultBundle.shouldPrioritizeRun(
        bundle.latestRuns.single,
        bundle.artifacts.single,
      ),
      isFalse,
    );
  });

  test('orders actionable severity before recency', () {
    final bundle = AgentResultBundle(
      artifacts: <AgentArtifact>[
        artifact(
          'recent-info',
          AgentArtifactSeverity.info,
          DateTime.utc(2026, 1, 3),
        ),
        artifact(
          'warning',
          AgentArtifactSeverity.warning,
          DateTime.utc(2026, 1, 1),
        ),
        artifact(
          'attention',
          AgentArtifactSeverity.attention,
          DateTime.utc(2026, 1, 2),
        ),
      ],
      latestRuns: const <AgentRunRecord>[],
    );

    expect(bundle.visibleEntries.map((entry) => entry.agentId), <String>[
      'warning',
      'attention',
      'recent-info',
    ]);
  });
}
