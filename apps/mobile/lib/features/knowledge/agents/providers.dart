/// KnowledgeOS agent providers (`docs/domains/knowledgeos-domain.md` §7).
///
/// Bootstrap consumes [knowledgeAgentsProvider] and concatenates the
/// list into the global `agentRegistryProvider` when the user has
/// opted into the Knowledge domain.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_presentation.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import 'assumption_agent.dart';
import 'contradiction_agent.dart';
import 'inbox_triage_agent.dart';
import 'review_agent.dart';

final reviewAgentProvider = Provider<ReviewAgent>((ref) => const ReviewAgent());

final assumptionAgentProvider = Provider<AssumptionAgent>(
  (ref) => const AssumptionAgent(),
);

final contradictionAgentProvider = Provider<ContradictionAgent>(
  (ref) => const ContradictionAgent(),
);

final inboxTriageAgentProvider = Provider<InboxTriageAgent>(
  (ref) => const InboxTriageAgent(),
);

/// Aggregated list — bootstrap composes this into the cross-domain
/// `agentRegistryProvider` only when Knowledge is opt-in.
final knowledgeAgentsProvider = Provider<List<Agent>>((ref) {
  return <Agent>[
    ref.watch(reviewAgentProvider),
    ref.watch(assumptionAgentProvider),
    ref.watch(contradictionAgentProvider),
    ref.watch(inboxTriageAgentProvider),
  ];
});

/// Most recent user-visible Knowledge Review artifact for the Review tab.
final latestKnowledgeReviewArtifactProvider =
    FutureProvider.autoDispose<AgentArtifact?>((ref) async {
      final bundle = await ref.watch(
        latestKnowledgeReviewResultsProvider.future,
      );
      return bundle.artifacts.isEmpty ? null : bundle.artifacts.first;
    });

/// Latest visible KnowledgeOS agent artifacts for the Review tab.
///
/// Knowledge contributes several review-placement agents (review, assumptions,
/// contradictions, inbox triage, routine due). The Review page renders this
/// list so all user-visible outputs share the same result card surface.
final latestKnowledgeReviewArtifactsProvider =
    FutureProvider.autoDispose<List<AgentArtifact>>((ref) async {
      final bundle = await ref.watch(
        latestKnowledgeReviewResultsProvider.future,
      );
      return bundle.artifacts;
    });

const _knowledgeReviewResultScope = agent_providers.AgentResultScope(
  domain: DomainScope.knowledge,
  placement: AgentResultPlacement.domainReview,
  limit: 5,
);

final latestKnowledgeReviewResultsProvider =
    FutureProvider.autoDispose<agent_providers.AgentResultBundle>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.knowledge)) {
        return agent_providers.AgentResultBundle.empty;
      }
      return ref.watch(
        agent_providers
            .latestAgentResultsForPlacementProvider(_knowledgeReviewResultScope)
            .future,
      );
    });

final latestKnowledgeReviewRunProvider =
    FutureProvider.autoDispose<AgentRunRecord?>((ref) async {
      final bundle = await ref.watch(
        latestKnowledgeReviewResultsProvider.future,
      );
      return bundle.latestRun;
    });
