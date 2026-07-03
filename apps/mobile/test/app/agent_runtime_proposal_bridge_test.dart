import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/proposals/agent_runtime_proposal_bridge.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';

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

  test(
    'AgentRuntimeConfirmedProposalRunner runs terminal step and applies proposal',
    () async {
      final applier = _RecordingApplier(
        state: const ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: 'action_1',
          appliedTable: 'execution_actions',
        ),
      );
      final runner = AgentRuntimeConfirmedProposalRunner(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: _TerminalBridge(step: _terminalProposalStep()),
          toolHost: AgentRuntimeToolHost(dispatcher: const _NoopDispatcher()),
        ),
        proposalBridge: AgentRuntimeProposalBridge(applier: applier),
      );

      final result = await runner.runAndApplyConfirmedProposal(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
      );

      expect(result['step'], containsPair('status', 'completed'));
      expect(result['proposal_apply'], containsPair('status', 'applied'));
      expect(applier.plans.single.proposalId, 'proposal_1');
    },
  );

  test(
    'AgentRuntimeConfirmedProposalRunner preserves skipped apply result',
    () async {
      final applier = _RecordingApplier();
      final runner = AgentRuntimeConfirmedProposalRunner(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: _TerminalBridge(
            step: const <String, Object?>{
              'status': 'completed',
              'output': <String, Object?>{'content': 'done'},
            },
          ),
          toolHost: AgentRuntimeToolHost(dispatcher: const _NoopDispatcher()),
        ),
        proposalBridge: AgentRuntimeProposalBridge(applier: applier),
      );

      final result = await runner.runAndApplyConfirmedProposal(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
      );

      expect(
        result['proposal_apply'],
        containsPair('reason', 'no_ready_proposal'),
      );
      expect(applier.plans, isEmpty);
    },
  );

  test(
    'agentRuntimeConfirmedProposalRunProvider runs confirmed proposal flow',
    () async {
      final applier = _RecordingApplier(
        state: const ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: 'action_1',
          appliedTable: 'execution_actions',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          agentRuntimeNativeBridgeProvider.overrideWithValue(
            _TerminalBridge(step: _terminalProposalStep()),
          ),
          agentRuntimeToolHostProvider.overrideWithValue(
            AgentRuntimeToolHost(dispatcher: const _NoopDispatcher()),
          ),
          proposalApplierProvider.overrideWith((ref) async => applier),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        agentRuntimeConfirmedProposalRunProvider(
          const AgentRuntimeConfirmedProposalRunRequest(
            catalog: <String, Object?>{'protocol_version': 'agent.v1'},
            request: <String, Object?>{'input': <String, Object?>{}},
            agentId: 'execution_review',
          ),
        ).future,
      );

      expect(result['step'], containsPair('status', 'completed'));
      expect(result['proposal_apply'], containsPair('status', 'applied'));
      expect(applier.plans.single.kind, 'execution_action');
    },
  );

  test(
    'agentRuntimeConfirmedProposalActiveCatalogRunProvider uses active catalog',
    () async {
      final applier = _RecordingApplier(
        state: const ProposalApplyState(status: ProposalApplyStatus.applied),
      );
      final bridge = _TerminalBridge(step: _terminalProposalStep());
      final container = ProviderContainer(
        overrides: [
          agentRuntimeCatalogProvider.overrideWithValue(
            AgentRuntimeCatalog(
              generatedAt: DateTime.utc(2026, 6, 29, 3, 0),
              activeDomains: const <String>['execution'],
              agents: const <AgentRuntimeAgentSpec>[],
              tools: const <AgentRuntimeToolSpec>[],
              proposalKinds: const <AgentRuntimeProposalKindSpec>[],
              promptBlocks: const <AgentRuntimePromptBlockSpec>[],
            ),
          ),
          agentRuntimeNativeBridgeProvider.overrideWithValue(bridge),
          agentRuntimeToolHostProvider.overrideWithValue(
            AgentRuntimeToolHost(dispatcher: const _NoopDispatcher()),
          ),
          proposalApplierProvider.overrideWith((ref) async => applier),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        agentRuntimeConfirmedProposalActiveCatalogRunProvider(
          const AgentRuntimeConfirmedProposalActiveCatalogRunRequest(
            request: <String, Object?>{'input': <String, Object?>{}},
            agentId: 'execution_review',
          ),
        ).future,
      );

      expect(result['proposal_apply'], containsPair('status', 'applied'));
      expect(bridge.catalogs.single['active_domains'], ['execution']);
    },
  );
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

class _TerminalBridge implements AgentRuntimeNativeBridge {
  _TerminalBridge({required Map<String, Object?> step}) : _step = step;

  final Map<String, Object?> _step;
  final catalogs = <Map<String, Object?>>[];

  @override
  Future<String> protocolVersion() async => 'agent.v1';

  @override
  Future<String> catalogVersion() async => 'agent_catalog.v1';

  @override
  Future<Map<String, Object?>> catalogSummary(
    Map<String, Object?> catalog,
  ) async {
    return catalog;
  }

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateToolSpec(
    Map<String, Object?> tool,
  ) async {
    return tool;
  }

  @override
  Future<Map<String, Object?>> validateLlmRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  ) async {
    return response;
  }

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    return trace;
  }

  @override
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  }) async {
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': request['provider'],
      'model': request['model'],
      'content': responseText,
      'finish_reason': 'stop',
    };
  }

  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) async {
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': request['provider'],
      'model': request['model'],
      'content': 'profile response',
      'finish_reason': 'stop',
    };
  }

  @override
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  }) async {
    catalogs.add(catalog);
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'llm_response': await completeProfileLlm(request: llmRequest),
      'step': _step,
    };
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    catalogs.add(catalog);
    return _step;
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    return _step;
  }
}

class _NoopDispatcher implements DeviceToolDispatcher {
  const _NoopDispatcher();

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    return const <String, Object?>{};
  }
}
