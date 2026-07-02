/// App factory for domain-facing agent-runtime tool-plan bindings.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/runtime/agent_runtime/agent_runtime_tool_plan_binding.dart';
import 'agent_runtime_catalog.dart';
import 'agent_runtime_step_runner.dart';
import 'agent_runtime_trace_recorder.dart';

export '../../core/ai/runtime/agent_runtime/agent_runtime_tool_plan_binding.dart'
    show
        AgentRuntimeNativeStepRunResult,
        AgentRuntimeToolPlanBinding,
        AgentRuntimeToolPlanStepRunner;

AgentRuntimeToolPlanBinding agentRuntimeToolPlanBinding(
  Ref ref, {
  required String agentId,
  required String domain,
  required String surface,
}) {
  return AgentRuntimeToolPlanBinding.lazyCatalog(
    agentId: agentId,
    domain: domain,
    surface: surface,
    stepRunnerReader: () => ref.read(agentRuntimeNativeStepRunnerProvider),
    catalogJsonReader: () => ref.read(agentRuntimeCatalogProvider).toJson(),
    recordTrace: ref
        .read(agentRuntimeTraceRecorderProvider)
        .stepRunRecorder(agentId: agentId, domain: domain, surface: surface),
  );
}
