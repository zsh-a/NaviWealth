/// Proposal application seam for FRB-backed agent-runtime results.
///
/// The native runner returns terminal JSON steps. When a caller has already
/// obtained user confirmation, this bridge parses a ready proposal envelope
/// from the terminal step and dispatches it through the existing cross-domain
/// [ProposalApplier]. It does not auto-apply during agent execution.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../composition/proposal_applier.dart';
import '../../composition/proposal_apply_state.dart';
import '../../composition/proposal_plan.dart';

final agentRuntimeProposalBridgeProvider =
    FutureProvider<AgentRuntimeProposalBridge>((ref) async {
      return AgentRuntimeProposalBridge(
        applier: await ref.watch(proposalApplierProvider.future),
      );
    });

class AgentRuntimeProposalBridge {
  const AgentRuntimeProposalBridge({required ProposalApplier applier})
    : _applier = applier;

  final ProposalApplier _applier;

  ReadyProposalPlan? terminalReadyProposal(Map<String, Object?> step) {
    return agentRuntimeTerminalReadyProposal(step);
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

ReadyProposalPlan? agentRuntimeTerminalReadyProposal(
  Map<String, Object?> step,
) {
  if (!_isTerminalStep(step)) return null;
  for (final candidate in _proposalCandidates(step)) {
    final plan = ProposalPlan.tryParse(candidate);
    if (plan is ReadyProposalPlan) return plan;
  }
  return null;
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
