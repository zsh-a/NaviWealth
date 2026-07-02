/// FRB-backed provider overrides for ExecutionOS agents.
library;

import 'package:flutter_riverpod/misc.dart' show Override;

import '../../features/execution/agents/providers.dart'
    as execution_agent_providers;
import '../../features/execution/agents/review_agent.dart';
import 'agent_runtime_tool_plan_binding.dart';

List<Override> agentRuntimeExecutionProviderOverrides() => <Override>[
  execution_agent_providers.executionReviewAgentProvider.overrideWith((ref) {
    return ExecutionReviewAgent(
      reviewReader: FrbExecutionReviewReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kExecutionReviewAgentId,
          domain: 'execution',
          surface: 'execution_review',
        ),
      ),
    );
  }),
];
