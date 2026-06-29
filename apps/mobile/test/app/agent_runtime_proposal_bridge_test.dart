import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_proposal_bridge.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';

void main() {
  test('parses ready proposal from terminal tool result', () {
    final bridge = AgentRuntimeProposalBridge(applier: _RecordingApplier());

    final plan = bridge.terminalReadyProposal(_terminalProposalStep());

    expect(plan, isA<ReadyProposalPlan>());
    expect(plan!.proposalId, 'proposal_1');
    expect(plan.kind, 'execution_action');
    expect(plan.payload, containsPair('title', 'Draft roadmap'));
  });

  test(
    'applyTerminalReadyProposal dispatches through proposal applier',
    () async {
      final applier = _RecordingApplier(
        state: ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: 'action_1',
          appliedTable: 'execution_actions',
          appliedAt: DateTime.utc(2026, 6, 29, 2, 0),
        ),
      );
      final bridge = AgentRuntimeProposalBridge(applier: applier);

      final result = await bridge.applyTerminalReadyProposal(
        _terminalProposalStep(),
      );

      expect(result['status'], 'applied');
      expect(result['proposal_id'], 'proposal_1');
      expect(result['kind'], 'execution_action');
      expect(
        result['apply_state'],
        containsPair('applied_entity_id', 'action_1'),
      );
      expect(applier.plans.single.summaryZh, 'Create action');
    },
  );

  test('does not parse proposals from non-terminal steps', () async {
    final applier = _RecordingApplier();
    final bridge = AgentRuntimeProposalBridge(applier: applier);

    final result = await bridge.applyTerminalReadyProposal(<String, Object?>{
      ..._terminalProposalStep(),
      'status': 'tool_call_requested',
    });

    expect(result, containsPair('status', 'skipped'));
    expect(result, containsPair('reason', 'no_ready_proposal'));
    expect(applier.plans, isEmpty);
  });

  test('does not apply clarification proposals', () async {
    final applier = _RecordingApplier();
    final bridge = AgentRuntimeProposalBridge(applier: applier);

    final result = await bridge.applyTerminalReadyProposal(<String, Object?>{
      'status': 'completed',
      'output': <String, Object?>{
        'tool_result': <String, Object?>{
          'proposal_id': 'proposal_2',
          'kind': 'execution_action',
          'status': 'needs_clarification',
          'ambiguous_field': 'project',
          'reason': 'Pick a project',
        },
      },
    });

    expect(result, containsPair('status', 'skipped'));
    expect(applier.plans, isEmpty);
  });

  test('returns structured error when applier throws', () async {
    final bridge = AgentRuntimeProposalBridge(
      applier: _RecordingApplier(error: ProposalApplyException('blocked')),
    );

    final result = await bridge.applyTerminalReadyProposal(
      _terminalProposalStep(),
    );

    expect(result['status'], 'errored');
    expect(result['proposal_id'], 'proposal_1');
    expect(result['apply_state'], containsPair('error_message', 'blocked'));
  });
}

Map<String, Object?> _terminalProposalStep() {
  return <String, Object?>{
    'status': 'completed',
    'output': <String, Object?>{
      'mode': 'frb_tool_step',
      'tool_result': <String, Object?>{
        'proposal_id': 'proposal_1',
        'kind': 'execution_action',
        'status': 'ready',
        'summary_zh': 'Create action',
        'payload': <String, Object?>{'title': 'Draft roadmap'},
      },
    },
  };
}

class _RecordingApplier implements ProposalApplier {
  _RecordingApplier({ProposalApplyState? state, Object? error})
    : _state =
          state ??
          const ProposalApplyState(status: ProposalApplyStatus.applied),
      _error = error;

  final ProposalApplyState _state;
  final Object? _error;
  final plans = <ReadyProposalPlan>[];

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    plans.add(plan);
    final error = _error;
    if (error != null) throw error;
    return _state;
  }

  @override
  Future<void> undo(ProposalApplyState state) async {}
}
