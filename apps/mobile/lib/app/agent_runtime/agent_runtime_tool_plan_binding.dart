/// Shared dependencies for Dart readers that execute native tool-plan steps.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_runtime_catalog.dart';
import 'agent_runtime_step_runner.dart';
import 'agent_runtime_trace_recorder.dart';

class AgentRuntimeToolPlanBinding {
  AgentRuntimeToolPlanBinding({
    required this.agentId,
    required this.domain,
    required this.surface,
    required this.stepRunner,
    required AgentRuntimeCatalog catalog,
    this.recordTrace,
  }) : _catalogReader = (() => catalog);

  const AgentRuntimeToolPlanBinding.lazyCatalog({
    required this.agentId,
    required this.domain,
    required this.surface,
    required this.stepRunner,
    required AgentRuntimeCatalog Function() catalogReader,
    this.recordTrace,
  }) : _catalogReader = catalogReader;

  final String agentId;
  final String domain;
  final String surface;
  final AgentRuntimeNativeStepRunner stepRunner;
  final AgentRuntimeStepTraceRecorder? recordTrace;
  final AgentRuntimeCatalog Function() _catalogReader;

  Future<AgentRuntimeNativeStepRunResult> runToolPlan({
    required List<Map<String, Object?>> toolPlan,
    String trigger = 'manual',
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxToolSteps,
  }) async {
    final catalog = _catalogReader();
    final stepRun = await stepRunner.runUntilTerminalWithTrace(
      catalog: catalog.toJson(),
      request: <String, Object?>{
        'protocol_version': kAgentRuntimeProtocolVersion,
        'input': <String, Object?>{
          'tool_plan': <Object?>[for (final toolCall in toolPlan) toolCall],
        },
        'trigger': trigger,
        'metadata': <String, Object?>{
          'surface': surface,
          'agent_id': agentId,
          ...metadata,
        },
      },
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    );
    await recordStepRun(stepRun);
    return stepRun;
  }

  Future<T> readFromToolPlan<T>({
    required List<Map<String, Object?>> toolPlan,
    required Future<T> Function() fallback,
    required FutureOr<T?> Function(Map<String, Object?> terminalStep) decode,
    String trigger = 'manual',
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxToolSteps,
  }) async {
    try {
      final stepRun = await runToolPlan(
        toolPlan: toolPlan,
        trigger: trigger,
        metadata: metadata,
        maxToolSteps: maxToolSteps,
      );
      final value = await decode(stepRun.terminalStep);
      if (value != null) return value;
    } on Object {
      // Fall through to the repository/programmatic path below.
    }
    return fallback();
  }

  Future<void> recordStepRun(AgentRuntimeNativeStepRunResult stepRun) async {
    final recorder = recordTrace;
    if (recorder == null) return;
    try {
      await recorder(stepRun);
    } on Object {
      // Best-effort diagnostics; never fail the production agent.
    }
  }
}

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
    stepRunner: ref.watch(agentRuntimeNativeStepRunnerProvider),
    catalogReader: () => ref.read(agentRuntimeCatalogProvider),
    recordTrace: ref
        .read(agentRuntimeTraceRecorderProvider)
        .stepRunRecorder(agentId: agentId, domain: domain, surface: surface),
  );
}
