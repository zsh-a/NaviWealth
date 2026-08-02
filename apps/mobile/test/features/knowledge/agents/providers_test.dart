import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_presentation.dart';
import 'package:naviwealth/core/ai/agents/agent_registry.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/knowledge/agents/assumption_agent.dart';
import 'package:naviwealth/features/knowledge/agents/providers.dart';
import 'package:naviwealth/features/knowledge/agents/review_agent.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('review result providers respect Knowledge opt-in', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final artifactStore = SqliteAgentArtifactStore(db: db);
    final runStore = SqliteAgentRunStore(db: db);
    final startedAt = DateTime.utc(2026, 7, 5, 9);
    await artifactStore.save(
      _knowledgeArtifact(id: 'knowledge-review-1', createdAt: startedAt),
    );
    await artifactStore.save(
      _knowledgeArtifact(
        id: 'knowledge-assumption-1',
        agentId: kKnowledgeAssumptionAgentId,
        createdAt: startedAt.add(const Duration(minutes: 5)),
      ),
    );
    await runStore.finishRun(
      ownerUserId: 'user-1',
      agent: const ReviewAgent(),
      runStartedAt: startedAt,
      result: AgentRunResult(
        agentId: kKnowledgeReviewAgentId,
        status: AgentRunStatus.completed,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(milliseconds: 20)),
        summary: 'Review due decisions',
        artifactId: 'knowledge-review-1',
        traceId: 'trace-knowledge-review',
      ),
      trigger: AgentRunTrigger.schedule,
    );
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        currentUserIdProvider.overrideWithValue(() async => 'user-1'),
        agent_providers.agentArtifactStoreProvider.overrideWith(
          (ref) async => artifactStore,
        ),
        agent_providers.agentRunStoreProvider.overrideWith(
          (ref) async => runStore,
        ),
        agentRegistrationProvider
            .overrideWithValue(const <DomainAgentRegistration>[
              DomainAgentRegistration(
                agent: ReviewAgent(),
                domain: DomainScope.knowledge,
              ),
              DomainAgentRegistration(
                agent: AssumptionAgent(),
                domain: DomainScope.knowledge,
              ),
            ]),
        agentPresentationSpecsProvider
            .overrideWithValue(const <String, AgentPresentationSpec>{
              kKnowledgeReviewAgentId: AgentPresentationSpec(
                agentId: kKnowledgeReviewAgentId,
                domain: DomainScope.knowledge,
                icon: Icons.check,
                label: _agentLabel,
                description: _agentDescription,
                placement: AgentResultPlacement.domainReview,
              ),
              kKnowledgeAssumptionAgentId: AgentPresentationSpec(
                agentId: kKnowledgeAssumptionAgentId,
                domain: DomainScope.knowledge,
                icon: Icons.check,
                label: _agentLabel,
                description: _agentDescription,
                placement: AgentResultPlacement.domainReview,
              ),
            }),
      ],
    );
    addTearDown(c.dispose);
    await c.read(auth.domainOptInsProvider.future);

    expect(await c.read(latestKnowledgeReviewArtifactProvider.future), isNull);
    expect(
      await c.read(latestKnowledgeReviewArtifactsProvider.future),
      isEmpty,
    );
    expect(await c.read(latestKnowledgeReviewRunProvider.future), isNull);

    await c
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.knowledge, true);
    c.invalidate(latestKnowledgeReviewArtifactProvider);
    c.invalidate(latestKnowledgeReviewArtifactsProvider);
    c.invalidate(latestKnowledgeReviewRunProvider);

    final artifact = await c.read(latestKnowledgeReviewArtifactProvider.future);
    final artifacts = await c.read(
      latestKnowledgeReviewArtifactsProvider.future,
    );
    final run = await c.read(latestKnowledgeReviewRunProvider.future);

    expect(artifact?.id, 'knowledge-assumption-1');
    expect(artifacts.map((artifact) => artifact.id), [
      'knowledge-assumption-1',
      'knowledge-review-1',
    ]);
    expect(run?.status, AgentRunLifecycleStatus.ready);
    expect(run?.traceId, 'trace-knowledge-review');
  });
}

String _agentLabel(_) => 'Knowledge Review';

String _agentDescription(_) => 'Knowledge Review';

AgentArtifact _knowledgeArtifact({
  required String id,
  required DateTime createdAt,
  String agentId = kKnowledgeReviewAgentId,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: 'user-1',
    agentId: agentId,
    domain: 'knowledge',
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.info,
    title: 'Knowledge Review',
    summary: 'Review due decisions',
    createdAt: createdAt,
  );
}
