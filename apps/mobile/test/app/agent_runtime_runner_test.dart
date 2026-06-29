import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_runner.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';

void main() {
  test(
    'AgentRuntimeProfileTurnRunner completes profile LLM then native step',
    () async {
      final native = _FakeNativeBridge(
        llmResponse: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'provider': 'openai',
          'model': 'gpt-test',
          'content': 'Summarized result',
          'finish_reason': 'stop',
          'metadata': <String, Object?>{'profile': true},
        },
      );
      final runner = _runner(native: native);

      final result = await runner.run(
        agentId: 'execution_review',
        messages: const <Map<String, Object?>>[
          <String, Object?>{'role': 'user', 'content': 'Summarize today'},
        ],
        metadata: const <String, Object?>{'trace_id': 'trace_1'},
      );

      expect(result.llmResponse['content'], 'Summarized result');
      expect(result.step['status'], 'completed');
      expect(result.stepRun.terminalStep['status'], 'completed');
      expect(result.stepRun.dispatchedToolCount, 0);
      expect(result.stepRun.steps.single['status'], 'completed');
      expect(native.llmRequests.single['provider'], 'openai');
      expect(native.turnRequests.single.agentId, 'execution_review');
      expect(
        native.turnRequests.single.catalog['catalog_version'],
        kAgentRuntimeCatalogVersion,
      );
      final input = native.turnRequests.single.initialStep['output'];
      expect(input, isA<Map<String, Object?>>());
      expect(
        input as Map<String, Object?>,
        containsPair('content', 'Summarized result'),
      );
      final requestMetadata = native.turnRequests.single.runMetadata;
      expect(requestMetadata, isA<Map<String, Object?>>());
      expect(requestMetadata, containsPair('trace_id', 'trace_1'));
    },
  );

  test(
    'AgentRuntimeProfileTurnRunner dispatches native tool call from LLM metadata',
    () async {
      final native = _FakeNativeBridge(
        llmResponse: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'provider': 'openai',
          'model': 'gpt-test',
          'content': 'Use local tool',
          'finish_reason': 'stop',
          'metadata': <String, Object?>{
            'tool_call': <String, Object?>{
              'tool_call_id': 'call_1',
              'name': 'read_task',
              'input': <String, Object?>{'id': 'task_1'},
            },
          },
        },
      );
      final dispatcher = _RecordingDispatcher();
      final runner = _runner(native: native, dispatcher: dispatcher);

      final result = await runner.run(
        agentId: 'execution_review',
        messages: const <Map<String, Object?>>[
          <String, Object?>{'role': 'user', 'content': 'Check task'},
        ],
        maxToolSteps: 1,
      );

      expect(result.step['status'], 'completed');
      expect(result.stepRun.dispatchedToolCount, 1);
      expect(result.stepRun.toolResponses.single, containsPair('id', 'call_1'));
      expect(result.toJson()['step_run'], isA<Map<String, Object?>>());
      expect(
        result.step['output'],
        containsPair('tool_result', <String, Object?>{
          'tool': 'read_task',
          'input': <String, Object?>{'id': 'task_1'},
        }),
      );
      expect(dispatcher.calls.single.name, 'read_task');
      expect(dispatcher.calls.single.input, <String, Object?>{'id': 'task_1'});
      expect(
        native.continuations.single.toolResponse,
        containsPair('id', 'call_1'),
      );
      final input = native.turnRequests.single.initialStep['tool_call'];
      expect(input as Map<String, Object?>, containsPair('name', 'read_task'));
      expect(
        native.turnRequests.single.initialStep,
        containsPair('tool_call', const <String, Object?>{
          'tool_call_id': 'call_1',
          'name': 'read_task',
          'input': <String, Object?>{'id': 'task_1'},
        }),
      );
    },
  );

  test('provider returns null when no usable profile bridge exists', () {
    final container = ProviderContainer(
      overrides: [agentRuntimeLlmBridgeProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);

    expect(container.read(agentRuntimeProfileTurnRunnerProvider), isNull);
  });

  test(
    'provider composes active catalog, profile LLM bridge, and step runner',
    () {
      final native = _FakeNativeBridge();
      final llmBridge = _llmBridge(native);
      final stepRunner = AgentRuntimeNativeStepRunner(
        bridge: native,
        toolHost: AgentRuntimeToolHost(dispatcher: _RecordingDispatcher()),
      );
      final container = ProviderContainer(
        overrides: [
          agentRuntimeCatalogProvider.overrideWithValue(_catalog()),
          agentRuntimeLlmBridgeProvider.overrideWithValue(llmBridge),
          agentRuntimeNativeStepRunnerProvider.overrideWithValue(stepRunner),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(agentRuntimeProfileTurnRunnerProvider), isNotNull);
    },
  );
}

AgentRuntimeProfileTurnRunner _runner({
  required _FakeNativeBridge native,
  _RecordingDispatcher? dispatcher,
}) {
  return AgentRuntimeProfileTurnRunner(
    catalog: _catalog(),
    llmBridge: _llmBridge(native),
    stepRunner: AgentRuntimeNativeStepRunner(
      bridge: native,
      toolHost: AgentRuntimeToolHost(
        dispatcher: dispatcher ?? _RecordingDispatcher(),
      ),
    ),
  );
}

AgentRuntimeLlmBridge _llmBridge(_FakeNativeBridge native) {
  return AgentRuntimeLlmBridge(
    bridge: native,
    profile: const LlmProfile(
      id: 'profile_1',
      name: 'Local profile',
      provider: LlmProvider.openai,
      apiKey: 'sk-test',
      model: 'gpt-test',
    ),
  );
}

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: DateTime.utc(2026, 6, 29, 8),
    activeDomains: const <String>['execution'],
    agents: const <AgentRuntimeAgentSpec>[],
    tools: const <AgentRuntimeToolSpec>[],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _FakeNativeBridge implements AgentRuntimeNativeBridge {
  _FakeNativeBridge({
    Map<String, Object?> llmResponse = const <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': 'openai',
      'model': 'gpt-test',
      'content': 'profile response',
      'finish_reason': 'stop',
      'metadata': <String, Object?>{'profile': true},
    },
  }) : _llmResponse = llmResponse;

  final Map<String, Object?> _llmResponse;
  final llmRequests = <Map<String, Object?>>[];
  final turnRequests = <_TurnRequest>[];
  final startRequests = <_StartRequest>[];
  final continuations = <_Continuation>[];

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
    llmRequests.add(request);
    return _llmResponse;
  }

  @override
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  }) async {
    llmRequests.add(llmRequest);
    final initialStep = _initialStepForLlmResponse(_llmResponse, agentId);
    turnRequests.add(
      _TurnRequest(catalog, llmRequest, agentId, runMetadata, initialStep),
    );
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'llm_response': _llmResponse,
      'step': initialStep,
    };
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    continuations.add(_Continuation(previousStep, toolResponse));
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'status': toolResponse['error'] == null ? 'completed' : 'failed',
      'tool_call': previousStep['tool_call'],
      'output': <String, Object?>{'tool_result': toolResponse['result']},
    };
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    startRequests.add(_StartRequest(catalog, request, agentId));
    final input = request['input'];
    if (input is Map<String, Object?>) {
      final toolCall = input['tool_call'];
      if (toolCall is Map<String, Object?>) {
        return <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': agentId,
          'status': 'tool_call_requested',
          'tool_call': toolCall,
        };
      }
    }
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': 'run_1',
      'agent_id': agentId,
      'status': 'completed',
      'output': input,
    };
  }

  Map<String, Object?> _initialStepForLlmResponse(
    Map<String, Object?> llmResponse,
    String agentId,
  ) {
    final metadata = llmResponse['metadata'];
    if (metadata is Map<String, Object?>) {
      final toolCall = metadata['tool_call'];
      if (toolCall is Map<String, Object?>) {
        return <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': agentId,
          'status': 'tool_call_requested',
          'tool_call': toolCall,
        };
      }
    }
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': 'run_1',
      'agent_id': agentId,
      'status': 'completed',
      'output': <String, Object?>{
        'content': llmResponse['content'],
        'llm_response': llmResponse,
      },
    };
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
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    return trace;
  }
}

class _RecordingDispatcher implements DeviceToolDispatcher {
  final calls = <_ToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(_ToolCall(name, input));
    return <String, Object?>{'tool': name, 'input': input};
  }
}

class _StartRequest {
  const _StartRequest(this.catalog, this.request, this.agentId);

  final Map<String, Object?> catalog;
  final Map<String, Object?> request;
  final String agentId;
}

class _TurnRequest {
  const _TurnRequest(
    this.catalog,
    this.llmRequest,
    this.agentId,
    this.runMetadata,
    this.initialStep,
  );

  final Map<String, Object?> catalog;
  final Map<String, Object?> llmRequest;
  final String agentId;
  final Map<String, Object?> runMetadata;
  final Map<String, Object?> initialStep;
}

class _Continuation {
  const _Continuation(this.previousStep, this.toolResponse);

  final Map<String, Object?> previousStep;
  final Map<String, Object?> toolResponse;
}

class _ToolCall {
  const _ToolCall(this.name, this.input);

  final String name;
  final Object? input;
}
