/// App factory for domain-facing agent-runtime effect-plan bindings.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/trace/agent_runtime_trace_recorder.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';

export 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart'
    show
        AgentRuntimeNativeStepRunResult,
        AgentRuntimeEffect,
        AgentRuntimeEffectPlanBinding,
        AgentRuntimeSubagentEffect,
        AgentRuntimeToolEffect,
        AgentRuntimeEffectStepRunner;

AgentRuntimeEffectPlanBinding agentRuntimeEffectPlanBinding(
  Ref ref, {
  required String agentId,
  required String domain,
  required String surface,
}) {
  return AgentRuntimeEffectPlanBinding.lazyCatalog(
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
