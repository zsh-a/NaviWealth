import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';

void main() {
  test(
    'FfiAgentRuntimeNativeBridge initializes once and decodes JSON',
    () async {
      final initCalls = <String?>[];
      final api = _FakeNativeApi();
      final bridge = FfiAgentRuntimeNativeBridge(
        api: api,
        libraryPath: '/tmp/liblifeos_native.dylib',
        initRuntime: ({String? libraryPath}) async {
          initCalls.add(libraryPath);
        },
      );

      expect(await bridge.protocolVersion(), 'agent.v1');
      expect(await bridge.catalogVersion(), 'agent_catalog.v1');

      final summary = await bridge.catalogSummary(const <String, Object?>{
        'protocol_version': 'agent.v1',
        'catalog_version': 'agent_catalog.v1',
        'agents': <Object?>[],
        'tools': <Object?>[],
      });

      expect(summary, containsPair('agent_count', 0));
      final llmRequest = await bridge.validateLlmRequest(
        const <String, Object?>{
          'protocol_version': 'agent.v1',
          'provider': 'mock',
          'model': 'mock-model',
          'messages': <Object?>[
            <String, Object?>{'role': 'user', 'content': 'hello'},
          ],
        },
      );
      expect(llmRequest, containsPair('provider', 'mock'));
      final llmResponse = await bridge.completeMockLlm(
        request: llmRequest,
        responseText: 'mock answer',
      );
      expect(llmResponse, containsPair('content', 'mock answer'));
      expect(
        await bridge.completeProfileLlm(request: llmRequest),
        containsPair('content', 'profile answer'),
      );
      final turn = await bridge.startProfileTurnStep(
        catalog: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'catalog_version': 'agent_catalog.v1',
        },
        llmRequest: llmRequest,
        agentId: 'execution_review',
        runMetadata: const <String, Object?>{'surface': 'test'},
      );
      expect(turn['llm_response'], containsPair('content', 'profile answer'));
      expect(turn['step'], containsPair('status', 'completed'));
      expect(
        await bridge.validateLlmResponse(llmResponse),
        containsPair('finish_reason', 'stop'),
      );
      final step = await bridge.startRunStep(
        catalog: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'catalog_version': 'agent_catalog.v1',
        },
        request: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'input': <String, Object?>{},
        },
        agentId: 'execution_review',
      );
      expect(step, containsPair('status', 'completed'));
      final continued = await bridge.continueRunStep(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        previousStep: const <String, Object?>{
          'run_id': 'run_1',
          'status': 'tool_call_requested',
        },
        toolResponse: const <String, Object?>{
          'jsonrpc': '2.0',
          'result': <String, Object?>{'ok': true},
        },
        agentId: 'execution_review',
      );
      expect(continued, containsPair('status', 'completed'));
      expect(initCalls, ['/tmp/liblifeos_native.dylib']);
      expect(
        api.catalogPayloads.single,
        contains('"protocol_version":"agent.v1"'),
      );
    },
  );

  test(
    'agentRuntimeNativeCatalogSummaryProvider sends active catalog',
    () async {
      final bridge = _FakeBridge();
      final container = ProviderContainer(
        overrides: [
          agentRuntimeCatalogProvider.overrideWithValue(
            AgentRuntimeCatalog(
              generatedAt: DateTime.utc(2026, 6, 28, 9, 12, 31),
              activeDomains: const <String>['finance'],
              agents: const <AgentRuntimeAgentSpec>[],
              tools: const <AgentRuntimeToolSpec>[],
              proposalKinds: const <AgentRuntimeProposalKindSpec>[],
              promptBlocks: const <AgentRuntimePromptBlockSpec>[],
            ),
          ),
          agentRuntimeNativeBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);

      final summary = await container.read(
        agentRuntimeNativeCatalogSummaryProvider.future,
      );

      expect(summary['protocol_version'], 'agent.v1');
      expect(summary['active_domains'], ['finance']);
      expect(bridge.catalogs.single['catalog_version'], 'agent_catalog.v1');
    },
  );

  test(
    'AgentRuntimeNativeStepRunner dispatches requested native tool call',
    () async {
      final dispatcher = _RecordingDispatcher();
      final bridge = _FakeBridge(
        step: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': 'execution_review',
          'status': 'tool_call_requested',
          'tool_call': <String, Object?>{
            'tool_call_id': 'call_1',
            'name': 'read_task',
            'input': <String, Object?>{'id': 'task_1'},
          },
        },
      );
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.startAndDispatchFirstToolStep(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
      );

      expect(result['status'], 'completed');
      expect(result['output'], containsPair('mode', 'fake_continue'));
      expect(
        result['output'],
        containsPair('tool_result', <String, Object?>{
          'tool': 'read_task',
          'input': <String, Object?>{'id': 'task_1'},
        }),
      );
      expect(dispatcher.calls.single.name, 'read_task');
      expect(dispatcher.calls.single.input, <String, Object?>{'id': 'task_1'});
      expect(result['tool_call'], containsPair('name', 'read_task'));
      expect(
        bridge.continuations.single.toolResponse,
        containsPair('id', 'call_1'),
      );
    },
  );

  test(
    'AgentRuntimeNativeStepRunner loops until native terminal step',
    () async {
      final dispatcher = _RecordingDispatcher();
      final bridge = _FakeBridge(
        step: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': 'execution_review',
          'step_index': 0,
          'status': 'tool_call_requested',
          'trace_event': <String, Object?>{
            'kind': 'agent_runtime_step',
            'step_index': 0,
          },
          'tool_call': <String, Object?>{
            'tool_call_id': 'call_1',
            'name': 'read_first',
            'input': <String, Object?>{'id': 'first'},
          },
        },
        continuationSteps: const <Map<String, Object?>>[
          <String, Object?>{
            'protocol_version': 'agent.v1',
            'run_id': 'run_1',
            'agent_id': 'execution_review',
            'status': 'tool_call_requested',
            'tool_call': <String, Object?>{
              'tool_call_id': 'call_2',
              'name': 'read_second',
              'input': <String, Object?>{'id': 'second'},
            },
          },
          <String, Object?>{
            'protocol_version': 'agent.v1',
            'run_id': 'run_1',
            'agent_id': 'execution_review',
            'step_index': 1,
            'status': 'completed',
            'trace_event': <String, Object?>{
              'kind': 'agent_runtime_step',
              'step_index': 1,
            },
            'output': <String, Object?>{'done': true},
          },
        ],
      );
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.runUntilTerminal(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
        maxToolSteps: 2,
      );

      expect(result['status'], 'completed');
      expect(result['output'], <String, Object?>{'done': true});
      expect(dispatcher.calls.map((call) => call.name), <String>[
        'read_first',
        'read_second',
      ]);
      expect(bridge.continuations, hasLength(2));
      expect(
        bridge.continuations.last.toolResponse,
        containsPair('id', 'call_2'),
      );
    },
  );

  test(
    'AgentRuntimeNativeStepRunner exposes native step trace for tool loops',
    () async {
      final dispatcher = _RecordingDispatcher();
      final bridge = _FakeBridge(
        step: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': 'execution_review',
          'step_index': 0,
          'status': 'tool_call_requested',
          'trace_event': <String, Object?>{
            'kind': 'agent_runtime_step',
            'step_index': 0,
          },
          'tool_call': <String, Object?>{
            'tool_call_id': 'call_1',
            'name': 'read_first',
            'input': <String, Object?>{'id': 'first'},
          },
        },
        continuationSteps: const <Map<String, Object?>>[
          <String, Object?>{
            'protocol_version': 'agent.v1',
            'run_id': 'run_1',
            'agent_id': 'execution_review',
            'step_index': 1,
            'status': 'completed',
            'trace_event': <String, Object?>{
              'kind': 'agent_runtime_step',
              'step_index': 1,
            },
            'output': <String, Object?>{'done': true},
          },
        ],
      );
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.runUntilTerminalWithTrace(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
      );

      expect(result.terminalStep['status'], 'completed');
      expect(result.dispatchedToolCount, 1);
      expect(result.budgetExhausted, isFalse);
      expect(result.steps.map((step) => step['status']), <Object?>[
        'tool_call_requested',
        'completed',
      ]);
      expect(result.toolResponses.single, containsPair('id', 'call_1'));
      expect(result.nativeTraceEvents.map((event) => event['step_index']), [
        0,
        1,
      ]);
      expect(
        result.toJson(),
        containsPair('native_trace_events', result.nativeTraceEvents),
      );
      expect(result.toJson(), containsPair('dispatched_tool_count', 1));
    },
  );

  test(
    'AgentRuntimeNativeStepRunner dispatches native tool-plan continuations',
    () async {
      final dispatcher = _RecordingDispatcher();
      final bridge = _ToolPlanBridge();
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.runUntilTerminal(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
        maxToolSteps: 2,
      );

      expect(result['status'], 'completed');
      expect(result['output'], containsPair('mode', 'frb_tool_loop'));
      expect(dispatcher.calls.map((call) => call.name), <String>[
        'read_first',
        'read_second',
      ]);
      expect(bridge.continuations, hasLength(2));
      expect(
        bridge.continuations.first.toolResponse,
        containsPair('id', 'call_1'),
      );
      expect(
        bridge.continuations.last.toolResponse,
        containsPair('id', 'call_2'),
      );
    },
  );

  test(
    'AgentRuntimeNativeStepRunner fails when tool-call budget is exhausted',
    () async {
      final dispatcher = _RecordingDispatcher();
      final runner = AgentRuntimeNativeStepRunner(
        bridge: _FakeBridge(
          step: const <String, Object?>{
            'protocol_version': 'agent.v1',
            'run_id': 'run_1',
            'agent_id': 'execution_review',
            'status': 'tool_call_requested',
            'tool_call': <String, Object?>{
              'tool_call_id': 'call_1',
              'name': 'read_task',
              'input': <String, Object?>{'id': 'task_1'},
            },
          },
        ),
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.runUntilTerminal(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
        maxToolSteps: 0,
      );

      expect(result['status'], 'failed');
      expect(
        result['error'],
        containsPair('code', 'tool_call_budget_exhausted'),
      );
      expect(dispatcher.calls, isEmpty);
    },
  );

  test(
    'AgentRuntimeNativeStepRunner trace marks exhausted tool budgets',
    () async {
      final dispatcher = _RecordingDispatcher();
      final runner = AgentRuntimeNativeStepRunner(
        bridge: _FakeBridge(
          step: const <String, Object?>{
            'protocol_version': 'agent.v1',
            'run_id': 'run_1',
            'agent_id': 'execution_review',
            'status': 'tool_call_requested',
            'tool_call': <String, Object?>{
              'tool_call_id': 'call_1',
              'name': 'read_task',
              'input': <String, Object?>{'id': 'task_1'},
            },
          },
        ),
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.runUntilTerminalWithTrace(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
        maxToolSteps: 0,
      );

      expect(result.terminalStep['status'], 'failed');
      expect(result.dispatchedToolCount, 0);
      expect(result.budgetExhausted, isTrue);
      expect(result.steps, hasLength(2));
      expect(result.toolResponses, isEmpty);
      expect(
        result.terminalStep['run_state'],
        containsPair('terminal_reason', 'closed_early'),
      );
      expect(
        result.terminalStep['run_state'],
        containsPair('tool_result_count', 0),
      );
    },
  );

  test(
    'AgentRuntimeNativeStepRunner returns non-tool steps unchanged',
    () async {
      final dispatcher = _RecordingDispatcher();
      const step = <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': 'run_1',
        'agent_id': 'execution_review',
        'status': 'completed',
        'output': <String, Object?>{'content': 'done'},
      };
      final runner = AgentRuntimeNativeStepRunner(
        bridge: _FakeBridge(step: step),
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.startAndDispatchFirstToolStep(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
      );

      expect(result, step);
      expect(dispatcher.calls, isEmpty);
    },
  );
}

class _FakeNativeApi implements AgentRuntimeNativeApi {
  final catalogPayloads = <String>[];

  @override
  Future<String> protocolVersion() async => 'agent.v1';

  @override
  Future<String> catalogVersion() async => 'agent_catalog.v1';

  @override
  Future<String> catalogSummary({required String catalogJson}) async {
    catalogPayloads.add(catalogJson);
    final catalog = jsonDecode(catalogJson) as Map<String, Object?>;
    return jsonEncode(<String, Object?>{
      'protocol_version': catalog['protocol_version'],
      'catalog_version': catalog['catalog_version'],
      'agent_count': (catalog['agents'] as List<Object?>).length,
      'tool_count': (catalog['tools'] as List<Object?>).length,
    });
  }

  @override
  Future<String> validateRunRequest({required String requestJson}) async {
    return requestJson;
  }

  @override
  Future<String> validateToolSpec({required String toolJson}) async {
    return toolJson;
  }

  @override
  Future<String> validateLlmRequest({required String requestJson}) async {
    return requestJson;
  }

  @override
  Future<String> validateLlmResponse({required String responseJson}) async {
    return responseJson;
  }

  @override
  Future<String> validateTrace({required String traceJson}) async {
    return traceJson;
  }

  @override
  Future<String> completeMockLlm({
    required String requestJson,
    required String responseText,
  }) async {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    return jsonEncode(<String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': request['provider'],
      'model': request['model'],
      'content': responseText,
      'finish_reason': 'stop',
      'metadata': <String, Object?>{'mock': true},
    });
  }

  @override
  Future<String> completeProfileLlm({required String requestJson}) async {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    return jsonEncode(<String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': request['provider'],
      'model': request['model'],
      'content': 'profile answer',
      'finish_reason': 'stop',
      'metadata': <String, Object?>{'profile': true},
    });
  }

  @override
  Future<String> startProfileTurnStep({
    required String catalogJson,
    required String llmRequestJson,
    required String agentId,
    required String runMetadataJson,
  }) async {
    final request = jsonDecode(llmRequestJson) as Map<String, Object?>;
    return jsonEncode(<String, Object?>{
      'protocol_version': 'agent.v1',
      'llm_response': <String, Object?>{
        'protocol_version': 'agent.v1',
        'provider': request['provider'],
        'model': request['model'],
        'content': 'profile answer',
        'finish_reason': 'stop',
      },
      'step': <String, Object?>{
        'protocol_version': 'agent.v1',
        'agent_id': agentId,
        'status': 'completed',
        'output': <String, Object?>{'content': 'profile answer'},
      },
    });
  }

  @override
  Future<String> startRunStep({
    required String catalogJson,
    required String requestJson,
    required String agentId,
  }) async {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    return jsonEncode(<String, Object?>{
      'protocol_version': 'agent.v1',
      'agent_id': agentId,
      'status': request['input'] == null ? 'failed' : 'completed',
    });
  }

  @override
  Future<String> continueRunStep({
    required String catalogJson,
    required String previousStepJson,
    required String toolResponseJson,
    required String agentId,
  }) async {
    final toolResponse = jsonDecode(toolResponseJson) as Map<String, Object?>;
    return jsonEncode(<String, Object?>{
      'protocol_version': 'agent.v1',
      'agent_id': agentId,
      'status': toolResponse['error'] == null ? 'completed' : 'failed',
      'output': <String, Object?>{'tool_result': toolResponse['result']},
    });
  }
}

class _FakeBridge implements AgentRuntimeNativeBridge {
  _FakeBridge({
    Map<String, Object?>? step,
    List<Map<String, Object?>> continuationSteps =
        const <Map<String, Object?>>[],
  }) : _continuationSteps = continuationSteps,
       _step =
           step ??
           const <String, Object?>{
             'protocol_version': 'agent.v1',
             'agent_id': 'execution_review',
             'status': 'completed',
           };

  final catalogs = <Map<String, Object?>>[];
  final continuations = <_Continuation>[];
  final Map<String, Object?> _step;
  final List<Map<String, Object?>> _continuationSteps;

  @override
  Future<String> protocolVersion() async => 'agent.v1';

  @override
  Future<String> catalogVersion() async => 'agent_catalog.v1';

  @override
  Future<Map<String, Object?>> catalogSummary(
    Map<String, Object?> catalog,
  ) async {
    catalogs.add(catalog);
    return <String, Object?>{
      'protocol_version': catalog['protocol_version'],
      'active_domains': catalog['active_domains'],
    };
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
      'metadata': <String, Object?>{'mock': true},
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
      'content': 'profile answer',
      'finish_reason': 'stop',
      'metadata': <String, Object?>{'profile': true},
    };
  }

  @override
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  }) async {
    final response = await completeProfileLlm(request: llmRequest);
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'llm_response': response,
      'step': _step,
    };
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    return _step;
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    continuations.add(_Continuation(previousStep, toolResponse));
    if (continuations.length <= _continuationSteps.length) {
      return _continuationSteps[continuations.length - 1];
    }
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'status': toolResponse['error'] == null ? 'completed' : 'failed',
      'tool_call': previousStep['tool_call'],
      'output': <String, Object?>{
        'mode': 'fake_continue',
        'tool_result': toolResponse['result'],
      },
    };
  }
}

class _ToolPlanBridge extends _FakeBridge {
  _ToolPlanBridge()
    : super(
        step: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': 'execution_review',
          'status': 'tool_call_requested',
          'tool_call': <String, Object?>{
            'tool_call_id': 'call_1',
            'name': 'read_first',
            'input': <String, Object?>{'id': 'first'},
          },
          'continuation': <String, Object?>{
            'tool_plan': <Object?>[
              <String, Object?>{
                'name': 'read_second',
                'input': <String, Object?>{'id': 'second'},
              },
            ],
            'tool_results': <Object?>[],
          },
        },
      );

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    continuations.add(_Continuation(previousStep, toolResponse));
    final continuation = previousStep['continuation'];
    if (continuation is Map<String, Object?>) {
      final plan = continuation['tool_plan'];
      if (plan is List<Object?> && plan.isNotEmpty) {
        final nextTool = plan.first! as Map<String, Object?>;
        return <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': previousStep['run_id'],
          'agent_id': agentId,
          'status': 'tool_call_requested',
          'tool_call': <String, Object?>{
            'tool_call_id': 'call_2',
            'name': nextTool['name'],
            'input': nextTool['input'],
          },
          'continuation': <String, Object?>{
            'tool_plan': const <Object?>[],
            'tool_results': <Object?>[
              <String, Object?>{
                'tool_call': previousStep['tool_call'],
                'tool_response': toolResponse,
              },
            ],
          },
        };
      }
    }
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'status': 'completed',
      'output': <String, Object?>{
        'mode': 'frb_tool_loop',
        'tool_result': toolResponse['result'],
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

class _ToolCall {
  const _ToolCall(this.name, this.input);

  final String name;
  final Object? input;
}

class _Continuation {
  const _Continuation(this.previousStep, this.toolResponse);

  final Map<String, Object?> previousStep;
  final Map<String, Object?> toolResponse;
}
