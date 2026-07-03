/// App-level confirmed proposal runner for FRB-backed agent-runtime results.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_proposal_bridge.dart';

export 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_proposal_bridge.dart';

final agentRuntimeConfirmedProposalRunnerProvider =
    FutureProvider<AgentRuntimeConfirmedProposalRunner>((ref) async {
      return AgentRuntimeConfirmedProposalRunner(
        stepRunner: ref.watch(agentRuntimeNativeStepRunnerProvider),
        proposalBridge: await ref.watch(
          agentRuntimeProposalBridgeProvider.future,
        ),
      );
    });

final agentRuntimeConfirmedProposalRunProvider =
    FutureProvider.family<
      Map<String, Object?>,
      AgentRuntimeConfirmedProposalRunRequest
    >((ref, request) async {
      final runner = await ref.watch(
        agentRuntimeConfirmedProposalRunnerProvider.future,
      );
      return runner.runAndApplyConfirmedProposal(
        catalog: request.catalog,
        request: request.request,
        agentId: request.agentId,
        maxToolSteps: request.maxToolSteps,
      );
    });

final agentRuntimeConfirmedProposalActiveCatalogRunProvider =
    FutureProvider.family<
      Map<String, Object?>,
      AgentRuntimeConfirmedProposalActiveCatalogRunRequest
    >((ref, request) {
      final catalog = ref.watch(agentRuntimeCatalogProvider);
      return ref.watch(
        agentRuntimeConfirmedProposalRunProvider(
          AgentRuntimeConfirmedProposalRunRequest(
            catalog: catalog.toJson(),
            request: request.request,
            agentId: request.agentId,
            maxToolSteps: request.maxToolSteps,
          ),
        ).future,
      );
    });

class AgentRuntimeConfirmedProposalRunRequest {
  const AgentRuntimeConfirmedProposalRunRequest({
    required this.catalog,
    required this.request,
    required this.agentId,
    this.maxToolSteps,
  });

  final Map<String, Object?> catalog;
  final Map<String, Object?> request;
  final String agentId;
  final int? maxToolSteps;
}

class AgentRuntimeConfirmedProposalActiveCatalogRunRequest {
  const AgentRuntimeConfirmedProposalActiveCatalogRunRequest({
    required this.request,
    required this.agentId,
    this.maxToolSteps,
  });

  final Map<String, Object?> request;
  final String agentId;
  final int? maxToolSteps;
}

class AgentRuntimeConfirmedProposalRunner {
  const AgentRuntimeConfirmedProposalRunner({
    required AgentRuntimeNativeStepRunner stepRunner,
    required AgentRuntimeProposalBridge proposalBridge,
  }) : _stepRunner = stepRunner,
       _proposalBridge = proposalBridge;

  final AgentRuntimeNativeStepRunner _stepRunner;
  final AgentRuntimeProposalBridge _proposalBridge;

  Future<Map<String, Object?>> runAndApplyConfirmedProposal({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxToolSteps,
  }) async {
    final step = await _stepRunner.runUntilTerminal(
      catalog: catalog,
      request: request,
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    );
    final apply = await _proposalBridge.applyTerminalReadyProposal(step);
    return <String, Object?>{'step': step, 'proposal_apply': apply};
  }
}
