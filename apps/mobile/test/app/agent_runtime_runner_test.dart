import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_checkpoint_store.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_runner.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
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
      expect(result.stepRun.dispatchedEffectCount, 0);
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

  test('AgentRuntimeProfileTurnRunner dispatches native tool call from LLM metadata', () async {
    final native = _FakeNativeBridge(
      llmResponse: const <String, Object?>{
        'protocol_version': 'agent.v1',
        'provider': 'openai',
        'model': 'gpt-test',
        'content': 'Use local tool',
        'finish_reason': 'stop',
        'metadata': <String, Object?>{
          'effects': <Object?>[
            <String, Object?>{
              'kind': 'tool',
              'effect_id': 'call_1',
              'name': 'read_task',
              'input': <String, Object?>{'id': 'task_1'},
            },
          ],
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
      maxEffectSteps: 1,
    );

    expect(result.step['status'], 'completed');
    expect(result.stepRun.dispatchedEffectCount, 1);
    expect(result.stepRun.effectResponses.single, containsPair('id', 'call_1'));
    expect(result.toJson()['step_run'], isA<Map<String, Object?>>());
    expect(
      result.step['output'],
      containsPair('effect_result', <String, Object?>{
        'tool': 'read_task',
        'input': <String, Object?>{'id': 'task_1'},
      }),
    );
    expect(dispatcher.calls.single.name, 'read_task');
    expect(dispatcher.calls.single.input, <String, Object?>{'id': 'task_1'});
    expect(
      native.continuations.single.effectResponse,
      containsPair('id', 'call_1'),
    );
    final input = native.turnRequests.single.initialStep['effect'];
    expect(input as Map<String, Object?>, containsPair('name', 'read_task'));
    expect(
      native.turnRequests.single.initialStep,
      containsPair('effect', const <String, Object?>{
        'kind': 'tool',
        'effect_id': 'call_1',
        'name': 'read_task',
        'input': <String, Object?>{'id': 'task_1'},
      }),
    );
  });

  test('AgentRuntimeProfileTurnRunner prefers Rust-owned snapshots', () async {
    final native = _FakeProfileSnapshotBridge();
    final runner = _runner(native: native);

    final result = await runner.run(
      agentId: 'execution_review',
      messages: const <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': 'Summarize today'},
      ],
      maxEffectSteps: 2,
    );

    expect(native.snapshotTurnCount, 1);
    expect(native.turnRequests, isEmpty);
    expect(native.lastMaxEffectSteps, 2);
    expect(native.lastMaxSubagentDepth, 4);
    expect(result.llmResponse['content'], 'profile response');
    expect(result.step['status'], 'completed');
    expect(result.stepRun.maxEffectSteps, 2);
    expect(result.stepRun.remainingEffectSteps, 2);
  });

  test(
    'AgentRuntimeProfileTurnRunner resumes without a second LLM call',
    () async {
      final store = InMemoryAgentRuntimeCheckpointStore();
      final native = _RecoverableProfileSnapshotBridge();
      final firstDispatcher = _RecordingDispatcher();
      final firstRunner = _runner(
        native: native,
        dispatcher: firstDispatcher,
        checkpointStore: store,
      );

      await expectLater(
        firstRunner.run(
          agentId: 'execution_review',
          messages: const <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'Resume this turn'},
          ],
        ),
        throwsStateError,
      );
      expect(firstDispatcher.calls, hasLength(1));
      expect(native.snapshotTurnCount, 1);

      final secondDispatcher = _RecordingDispatcher();
      final resumed =
          await _runner(
            native: native,
            dispatcher: secondDispatcher,
            checkpointStore: store,
          ).run(
            agentId: 'execution_review',
            messages: const <Map<String, Object?>>[
              <String, Object?>{'role': 'user', 'content': 'Resume this turn'},
            ],
          );

      expect(resumed.llmResponse['content'], 'profile response');
      expect(resumed.step['status'], 'completed');
      expect(secondDispatcher.calls, isEmpty);
      expect(native.snapshotTurnCount, 1);
    },
  );

  test(
    'AgentRuntimeProfileTurnRunner rejects mismatched native turn protocol',
    () async {
      final native = _FakeNativeBridge(nativeTurnProtocolVersion: 'agent.v0');
      final runner = _runner(native: native);

      await expectLater(
        runner.run(
          agentId: 'execution_review',
          messages: const <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': 'Summarize today'},
          ],
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('protocol_version'),
          ),
        ),
      );
    },
  );

  test(
    'AgentRuntimeProfileTurnRunner rejects malformed native turn fields',
    () {
      Future<void> expectMalformedField({
        required Object? llmResponse,
        required Object? step,
        required String expectedMessage,
      }) async {
        final native = _FakeNativeBridge(
          nativeTurnLlmResponse: llmResponse,
          nativeTurnStep: step,
        );
        final runner = _runner(native: native);

        await expectLater(
          runner.run(
            agentId: 'execution_review',
            messages: const <Map<String, Object?>>[
              <String, Object?>{'role': 'user', 'content': 'Summarize today'},
            ],
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(expectedMessage),
            ),
          ),
        );
      }

      return expectMalformedField(
        llmResponse: 'bad',
        step: const <String, Object?>{'status': 'completed'},
        expectedMessage: 'field llm_response is not object',
      ).then((_) {
        return expectMalformedField(
          llmResponse: const <String, Object?>{'content': 'ok'},
          step: 'bad',
          expectedMessage: 'field snapshot is not object',
        );
      });
    },
  );

  test('provider returns null when no usable profile bridge exists', () {
    final container = ProviderContainer(
      overrides: [
        agentRuntimeLlmBridgeProvider.overrideWithValue(null),
        agentRuntimeProfileTurnRunnerProvider.overrideWith(
          buildAgentRuntimeProfileTurnRunner,
        ),
      ],
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
          agentRuntimeProfileTurnRunnerProvider.overrideWith(
            buildAgentRuntimeProfileTurnRunner,
          ),
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
  AgentRuntimeCheckpointStore? checkpointStore,
}) {
  return AgentRuntimeProfileTurnRunner(
    catalog: _catalog(),
    llmBridge: _llmBridge(native),
    stepRunner: AgentRuntimeNativeStepRunner(
      bridge: native,
      toolHost: AgentRuntimeToolHost(
        dispatcher: dispatcher ?? _RecordingDispatcher(),
      ),
      checkpointStore: checkpointStore,
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

class _FakeNativeBridge implements AgentRuntimeHostBridge {
  _FakeNativeBridge({
    Map<String, Object?> llmResponse = const <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': 'openai',
      'model': 'gpt-test',
      'content': 'profile response',
      'finish_reason': 'stop',
      'metadata': <String, Object?>{'profile': true},
    },
    this.nativeTurnProtocolVersion = kAgentRuntimeProtocolVersion,
    Object? nativeTurnLlmResponse,
    Object? nativeTurnStep,
  }) : _llmResponse = llmResponse,
       _nativeTurnLlmResponse = nativeTurnLlmResponse,
       _nativeTurnStep = nativeTurnStep;

  final Map<String, Object?> _llmResponse;
  final String nativeTurnProtocolVersion;
  final Object? _nativeTurnLlmResponse;
  final Object? _nativeTurnStep;
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
  Future<Map<String, Object?>> startProfileTurnSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async {
    llmRequests.add(llmRequest);
    final initialStep = _initialStepForLlmResponse(_llmResponse, agentId);
    turnRequests.add(
      _TurnRequest(catalog, llmRequest, agentId, runMetadata, initialStep),
    );
    return <String, Object?>{
      'protocol_version': nativeTurnProtocolVersion,
      'llm_response': _nativeTurnLlmResponse ?? _llmResponse,
      'snapshot':
          _nativeTurnStep ??
          _snapshotForStep(
            initialStep,
            maxEffectSteps: maxEffectSteps,
            maxSubagentDepth: maxSubagentDepth,
          ),
    };
  }

  @override
  Future<Map<String, Object?>> continueRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) async {
    final previousStep = Map<String, Object?>.from(snapshot['step']! as Map);
    continuations.add(_Continuation(previousStep, effectResponse));
    final limits = Map<String, Object?>.from(snapshot['limits']! as Map);
    return _snapshotForStep(
      <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': previousStep['run_id'],
        'agent_id': agentId,
        'step_index': 1,
        'status': effectResponse['error'] == null ? 'completed' : 'failed',
        'output': <String, Object?>{
          'effect': previousStep['effect'],
          'effect_result': effectResponse['result'],
          'effect_response': effectResponse,
        },
      },
      maxEffectSteps: limits['max_effect_steps']! as int,
      maxSubagentDepth: limits['max_subagent_depth']! as int,
      dispatchedEffectCount: 1,
    );
  }

  @override
  Future<Map<String, Object?>> startRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async {
    startRequests.add(_StartRequest(catalog, request, agentId));
    final input = request['input'];
    if (input is Map<String, Object?>) {
      final effect = input['effect'];
      if (effect is Map<String, Object?>) {
        return _snapshotForStep(
          <String, Object?>{
            'protocol_version': 'agent.v1',
            'run_id': 'run_1',
            'agent_id': agentId,
            'step_index': 0,
            'status': 'effect_requested',
            'effect': effect,
          },
          maxEffectSteps: maxEffectSteps,
          maxSubagentDepth: maxSubagentDepth,
        );
      }
    }
    return _snapshotForStep(
      <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': 'run_1',
        'agent_id': agentId,
        'step_index': 0,
        'status': 'completed',
        'output': input,
      },
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    );
  }

  @override
  Future<Map<String, Object?>> cancelRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required String agentId,
    required String reason,
  }) async => snapshot;

  @override
  Future<Map<String, Object?>> startRequestedSubagentSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> parentSnapshot,
  }) => throw UnsupportedError('subagent not used by this fake');

  @override
  Future<Map<String, Object?>> resumeParentFromSubagentSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> parentSnapshot,
    required Map<String, Object?> childSnapshot,
  }) => throw UnsupportedError('subagent not used by this fake');

  Map<String, Object?> _initialStepForLlmResponse(
    Map<String, Object?> llmResponse,
    String agentId,
  ) {
    final metadata = llmResponse['metadata'];
    if (metadata is Map<String, Object?>) {
      final effects = metadata['effects'];
      final effect = effects is List && effects.isNotEmpty
          ? effects.first
          : null;
      if (effect is Map<String, Object?>) {
        return <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': agentId,
          'status': 'effect_requested',
          'effect': effect,
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

Map<String, Object?> _snapshotForStep(
  Map<String, Object?> step, {
  required int maxEffectSteps,
  required int maxSubagentDepth,
  int dispatchedEffectCount = 0,
}) => <String, Object?>{
  'protocol_version': 'agent.v1',
  'snapshot_version': 1,
  'step': step,
  'limits': <String, Object?>{
    'max_effect_steps': maxEffectSteps,
    'max_subagent_depth': maxSubagentDepth,
  },
  'progress': <String, Object?>{
    'dispatched_effect_count': dispatchedEffectCount,
    'subagent_depth': 0,
    'effect_budget_exhausted': false,
    'subagent_depth_exceeded': false,
  },
};

class _FakeProfileSnapshotBridge extends _FakeNativeBridge
    implements AgentRuntimeSnapshotBridge {
  int snapshotTurnCount = 0;
  int? lastMaxEffectSteps;
  int? lastMaxSubagentDepth;

  @override
  Future<Map<String, Object?>> startProfileTurnSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async {
    snapshotTurnCount += 1;
    lastMaxEffectSteps = maxEffectSteps;
    lastMaxSubagentDepth = maxSubagentDepth;
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'llm_response': _llmResponse,
      'snapshot': _terminalSnapshot(
        agentId: agentId,
        maxEffectSteps: maxEffectSteps,
        maxSubagentDepth: maxSubagentDepth,
      ),
    };
  }

  @override
  Future<Map<String, Object?>> startRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async {
    return _terminalSnapshot(
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    );
  }

  @override
  Future<Map<String, Object?>> continueRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) {
    throw UnsupportedError('continuation not used by this fake');
  }

  @override
  Future<Map<String, Object?>> startRequestedSubagentSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> parentSnapshot,
  }) {
    throw UnsupportedError('subagent not used by this fake');
  }

  @override
  Future<Map<String, Object?>> resumeParentFromSubagentSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> parentSnapshot,
    required Map<String, Object?> childSnapshot,
  }) {
    throw UnsupportedError('subagent not used by this fake');
  }

  Map<String, Object?> _terminalSnapshot({
    required String agentId,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) {
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'snapshot_version': 1,
      'step': <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': 'snapshot_turn',
        'agent_id': agentId,
        'step_index': 0,
        'status': 'completed',
        'output': <String, Object?>{'content': _llmResponse['content']},
      },
      'limits': <String, Object?>{
        'max_effect_steps': maxEffectSteps,
        'max_subagent_depth': maxSubagentDepth,
      },
      'progress': const <String, Object?>{
        'dispatched_effect_count': 0,
        'subagent_depth': 0,
        'effect_budget_exhausted': false,
        'subagent_depth_exceeded': false,
      },
    };
  }
}

class _RecoverableProfileSnapshotBridge extends _FakeProfileSnapshotBridge {
  bool failNextContinuation = true;

  @override
  Future<Map<String, Object?>> startProfileTurnSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async {
    snapshotTurnCount += 1;
    lastMaxEffectSteps = maxEffectSteps;
    lastMaxSubagentDepth = maxSubagentDepth;
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'llm_response': _llmResponse,
      'snapshot': <String, Object?>{
        'protocol_version': 'agent.v1',
        'snapshot_version': 1,
        'step': <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'recoverable_profile_turn',
          'agent_id': agentId,
          'step_index': 0,
          'status': 'effect_requested',
          'effect': const <String, Object?>{
            'kind': 'tool',
            'effect_id': 'profile_effect_1',
            'name': 'read_profile_context',
            'input': <String, Object?>{},
          },
        },
        'limits': <String, Object?>{
          'max_effect_steps': maxEffectSteps,
          'max_subagent_depth': maxSubagentDepth,
        },
        'progress': const <String, Object?>{
          'dispatched_effect_count': 0,
          'subagent_depth': 0,
          'effect_budget_exhausted': false,
          'subagent_depth_exceeded': false,
        },
      },
    };
  }

  @override
  Future<Map<String, Object?>> continueRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) async {
    if (failNextContinuation) {
      failNextContinuation = false;
      throw StateError('simulated profile continuation crash');
    }
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'snapshot_version': 1,
      'step': <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': 'recoverable_profile_turn',
        'agent_id': agentId,
        'step_index': 1,
        'status': 'completed',
        'output': <String, Object?>{'effect_result': effectResponse['result']},
      },
      'limits': <String, Object?>{
        'max_effect_steps': lastMaxEffectSteps,
        'max_subagent_depth': lastMaxSubagentDepth,
      },
      'progress': const <String, Object?>{
        'dispatched_effect_count': 1,
        'subagent_depth': 0,
        'effect_budget_exhausted': false,
        'subagent_depth_exceeded': false,
      },
    };
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
  const _Continuation(this.previousStep, this.effectResponse);

  final Map<String, Object?> previousStep;
  final Map<String, Object?> effectResponse;
}

class _ToolCall {
  const _ToolCall(this.name, this.input);

  final String name;
  final Object? input;
}
