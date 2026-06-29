/// Proposal application seam for FRB-backed agent-runtime results.
///
/// The native runner returns terminal JSON steps. When a caller has already
/// obtained user confirmation, this bridge parses a ready proposal envelope
/// from the terminal step and dispatches it through the existing cross-domain
/// [ProposalApplier]. It does not auto-apply during agent execution.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/composition/proposal_applier.dart';
import '../core/ai/composition/proposal_apply_state.dart';
import '../core/ai/composition/proposal_plan.dart';
import 'agent_runtime_catalog.dart';
import 'agent_runtime_native_bridge.dart';

final agentRuntimeProposalBridgeProvider =
    FutureProvider<AgentRuntimeProposalBridge>((ref) async {
      return AgentRuntimeProposalBridge(
        applier: await ref.watch(proposalApplierProvider.future),
      );
    });

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

class AgentRuntimeProposalBridge {
  const AgentRuntimeProposalBridge({required ProposalApplier applier})
    : _applier = applier;

  final ProposalApplier _applier;

  ReadyProposalPlan? terminalReadyProposal(Map<String, Object?> step) {
    if (!_isTerminalStep(step)) return null;
    for (final candidate in _proposalCandidates(step)) {
      final plan = ProposalPlan.tryParse(candidate);
      if (plan is ReadyProposalPlan) return plan;
    }
    return null;
  }

  Future<Map<String, Object?>> applyTerminalReadyProposal(
    Map<String, Object?> step,
  ) async {
    final plan = terminalReadyProposal(step);
    if (plan == null) {
      return const <String, Object?>{
        'status': 'skipped',
        'reason': 'no_ready_proposal',
      };
    }

    try {
      final state = await _applier.apply(plan);
      return <String, Object?>{
        'status': state.status.wire,
        'proposal_id': plan.proposalId,
        'kind': plan.kind,
        'apply_state': state.toJson(),
      };
    } on ProposalApplyException catch (e) {
      return _proposalApplyError(plan, e.message);
    } catch (e) {
      return _proposalApplyError(plan, '$e');
    }
  }
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

bool _isTerminalStep(Map<String, Object?> step) {
  return switch (step['status']) {
    'completed' || 'failed' || 'skipped' || 'cancelled' || 'timed_out' => true,
    _ => false,
  };
}

Iterable<Object?> _proposalCandidates(Map<String, Object?> step) sync* {
  yield step['proposal'];
  yield step['tool_result'];
  final output = step['output'];
  if (output is Map) {
    final normalized = output.map((k, v) => MapEntry(k.toString(), v));
    yield normalized['proposal'];
    yield normalized['tool_result'];
    yield normalized;
  }
}

Map<String, Object?> _proposalApplyError(
  ReadyProposalPlan plan,
  String message,
) {
  return <String, Object?>{
    'status': ProposalApplyStatus.errored.wire,
    'proposal_id': plan.proposalId,
    'kind': plan.kind,
    'apply_state': ProposalApplyState(
      status: ProposalApplyStatus.errored,
      errorMessage: message,
      shortLabel: plan.summaryZh,
    ).toJson(),
  };
}
