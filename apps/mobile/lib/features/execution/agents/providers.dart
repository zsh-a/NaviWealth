/// ExecutionOS agent providers.
///
/// Bootstrap consumes [executionAgentsProvider] through the Execution
/// DomainPack, so agents are registered only when Execution is active.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import 'review_agent.dart';

final executionReviewAgentProvider = Provider<ExecutionReviewAgent>(
  (ref) => const ExecutionReviewAgent(),
);

final executionAgentsProvider = Provider<List<Agent>>((ref) {
  return <Agent>[ref.watch(executionReviewAgentProvider)];
});
