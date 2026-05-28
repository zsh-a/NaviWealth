/// KnowledgeOS agent providers (`docs/knowledgeos-domain.md` §7).
///
/// Bootstrap consumes [knowledgeAgentsProvider] and concatenates the
/// list into the global `agentRegistryProvider` when the user has
/// opted into the Knowledge domain.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import 'assumption_agent.dart';
import 'contradiction_agent.dart';
import 'review_agent.dart';

final reviewAgentProvider = Provider<ReviewAgent>(
  (ref) => const ReviewAgent(),
);

final assumptionAgentProvider = Provider<AssumptionAgent>(
  (ref) => const AssumptionAgent(),
);

final contradictionAgentProvider = Provider<ContradictionAgent>(
  (ref) => const ContradictionAgent(),
);

/// Aggregated list — bootstrap composes this into the cross-domain
/// `agentRegistryProvider` only when Knowledge is opt-in.
final knowledgeAgentsProvider = Provider<List<Agent>>((ref) {
  return <Agent>[
    ref.watch(reviewAgentProvider),
    ref.watch(assumptionAgentProvider),
    ref.watch(contradictionAgentProvider),
  ];
});
