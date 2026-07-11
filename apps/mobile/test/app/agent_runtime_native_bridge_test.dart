import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_storage_policy.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
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
          'status': 'effect_requested',
        },
        effectResponse: const <String, Object?>{
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
    'agentRuntimeStoragePolicyProvider defaults to app-owned persistence',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final policy = container.read(agentRuntimeStoragePolicyProvider);

      expect(policy.mode, AgentRuntimeStorageMode.appOwned);
      expect(policy.storePath, isNull);
    },
  );

  test(
    'FfiAgentRuntimeNativeBridge rejects runtime-owned SQLite policy',
    () async {
      var initCalls = 0;
      final bridge = FfiAgentRuntimeNativeBridge(
        api: _FakeNativeApi(),
        initRuntime: ({String? libraryPath}) async {
          initCalls += 1;
        },
        storagePolicy: const AgentRuntimeStoragePolicy.runtimeOwnedSqliteDebug(
          storePath: '/tmp/runtime.sqlite',
        ),
      );

      await expectLater(
        bridge.protocolVersion(),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('app-owned Drift persistence'),
          ),
        ),
      );
      expect(initCalls, 0);
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
    'AgentRuntimeNativeStepRunner dispatches requested native effect',
    () async {
      final dispatcher = _RecordingDispatcher();
      final bridge = _FakeBridge(
        step: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': 'execution_review',
          'status': 'effect_requested',
          'effect': <String, Object?>{
            'kind': 'tool',
            'effect_id': 'call_1',
            'name': 'read_task',
            'input': <String, Object?>{'id': 'task_1'},
          },
        },
      );
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.startAndDispatchFirstEffectStep(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
      );

      expect(result['status'], 'completed');
      expect(result['output'], containsPair('mode', 'fake_continue'));
      expect(
        result['output'],
        containsPair('effect_result', <String, Object?>{
          'tool': 'read_task',
          'input': <String, Object?>{'id': 'task_1'},
        }),
      );
      expect(dispatcher.calls.single.name, 'read_task');
      expect(dispatcher.calls.single.input, <String, Object?>{'id': 'task_1'});
      expect(result['effect'], containsPair('name', 'read_task'));
      expect(
        bridge.continuations.single.effectResponse,
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
          'status': 'effect_requested',
          'trace_event': <String, Object?>{
            'kind': 'agent_runtime_step',
            'step_index': 0,
          },
          'effect': <String, Object?>{
            'kind': 'tool',
            'effect_id': 'call_1',
            'name': 'read_first',
            'input': <String, Object?>{'id': 'first'},
          },
        },
        continuationSteps: const <Map<String, Object?>>[
          <String, Object?>{
            'protocol_version': 'agent.v1',
            'run_id': 'run_1',
            'agent_id': 'execution_review',
            'status': 'effect_requested',
            'effect': <String, Object?>{
              'kind': 'tool',
              'effect_id': 'call_2',
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
        maxEffectSteps: 2,
      );

      expect(result['status'], 'completed');
      expect(result['output'], <String, Object?>{'done': true});
      expect(dispatcher.calls.map((call) => call.name), <String>[
        'read_first',
        'read_second',
      ]);
      expect(bridge.continuations, hasLength(2));
      expect(
        bridge.continuations.last.effectResponse,
        containsPair('id', 'call_2'),
      );
    },
  );

  test(
    'AgentRuntimeNativeStepRunner exposes native step trace for effect loops',
    () async {
      final dispatcher = _RecordingDispatcher();
      final bridge = _FakeBridge(
        step: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': 'execution_review',
          'step_index': 0,
          'status': 'effect_requested',
          'trace_event': <String, Object?>{
            'kind': 'agent_runtime_step',
            'step_index': 0,
          },
          'effect': <String, Object?>{
            'kind': 'tool',
            'effect_id': 'call_1',
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
      expect(result.dispatchedEffectCount, 1);
      expect(result.budgetExhausted, isFalse);
      expect(result.steps.map((step) => step['status']), <Object?>[
        'effect_requested',
        'completed',
      ]);
      expect(result.effectResponses.single, containsPair('id', 'call_1'));
      expect(result.nativeTraceEvents.map((event) => event['step_index']), [
        0,
        1,
      ]);
      expect(
        result.toJson(),
        containsPair('native_trace_events', result.nativeTraceEvents),
      );
      expect(result.toJson(), containsPair('dispatched_effect_count', 1));
    },
  );

  test(
    'AgentRuntimeNativeStepRunner dispatches native effect continuations',
    () async {
      final dispatcher = _RecordingDispatcher();
      final bridge = _EffectPlanBridge();
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.runUntilTerminal(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
        maxEffectSteps: 2,
      );

      expect(result['status'], 'completed');
      expect(result['output'], containsPair('mode', 'frb_effect_loop'));
      expect(dispatcher.calls.map((call) => call.name), <String>[
        'read_first',
        'read_second',
      ]);
      expect(bridge.continuations, hasLength(2));
      expect(
        bridge.continuations.first.effectResponse,
        containsPair('id', 'call_1'),
      );
      expect(
        bridge.continuations.last.effectResponse,
        containsPair('id', 'call_2'),
      );
    },
  );

  test(
    'AgentRuntimeNativeStepRunner dispatches native subagent effects',
    () async {
      final bridge = _SubagentBridge();
      final dispatcher = _RecordingDispatcher();
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.runUntilTerminalWithTrace(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'parent',
        maxEffectSteps: 2,
      );

      expect(result.terminalStep['status'], 'completed');
      expect(bridge.startedAgents, <String>['parent', 'child']);
      expect(bridge.startedRequests.last['run_id'], 'child_run');
      expect(bridge.startedRequests.last['input'], <String, Object?>{
        'from': 'parent',
      });
      expect(bridge.continuations, hasLength(1));
      expect(
        bridge.continuations.single.previousStep['status'],
        'effect_requested',
      );
      expect(
        bridge.continuations.single.effectResponse,
        containsPair('id', 'subagent_1'),
      );
      expect(
        bridge.continuations.single.effectResponse['result'],
        containsPair('agent_id', 'child'),
      );
      expect(
        result.effectResponses.single['result'],
        containsPair('terminal_step', containsPair('agent_id', 'child')),
      );
      expect(dispatcher.calls, isEmpty);
    },
  );

  test(
    'AgentRuntimeNativeStepRunner rejects subagents over max depth',
    () async {
      final bridge = _SubagentBridge();
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: _RecordingDispatcher()),
        defaultMaxSubagentDepth: 0,
      );

      final result = await runner.runUntilTerminalWithTrace(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'parent',
        maxEffectSteps: 2,
      );

      expect(result.subagentDepthExceeded, isTrue);
      expect(bridge.startedAgents, <String>['parent']);
      final response = bridge.continuations.single.effectResponse;
      expect(
        (response['result'] as Map)['error'],
        containsPair('code', 'subagent_depth_exceeded'),
      );
    },
  );

  test(
    'AgentRuntimeNativeStepRunner shares effect budget with subagents',
    () async {
      final bridge = _SubagentBudgetBridge();
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: _RecordingDispatcher()),
      );

      final result = await runner.runUntilTerminalWithTrace(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'parent',
        maxEffectSteps: 1,
      );

      expect(result.budgetExhausted, isTrue);
      expect(result.dispatchedEffectCount, 1);
      expect(bridge.startedAgents, <String>['parent', 'child']);
      final childResult =
          result.effectResponses.single['result'] as Map<String, Object?>;
      expect(childResult['budget_exhausted'], true);
      expect(childResult['remaining_effect_steps'], 0);
    },
  );

  test(
    'AgentRuntimeNativeStepRunner lets native classify effect response errors',
    () async {
      final dispatcher = _RecordingDispatcher(
        output: const <String, Object?>{
          'error': <String, Object?>{
            'code': 'policy_denied',
            'policy': 'confirmation_required',
            'message': 'confirmation required',
          },
          'policy_denied': true,
        },
      );
      final bridge = _FakeBridge(
        step: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': 'execution_review',
          'status': 'effect_requested',
          'effect': <String, Object?>{
            'kind': 'tool',
            'effect_id': 'call_1',
            'name': 'read_task',
            'input': <String, Object?>{'id': 'task_1'},
          },
        },
      );
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.runUntilTerminalWithTrace(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
        maxEffectSteps: 1,
      );

      expect(result.terminalStep['status'], 'policy_denied');
      expect(result.dispatchedEffectCount, 1);
      expect(result.budgetExhausted, isFalse);
      expect(bridge.continuations, hasLength(1));
      expect(
        bridge.continuations.single.effectResponse['result'],
        containsPair('policy_denied', true),
      );
      expect(
        result.terminalStep['run_state'],
        containsPair('terminal_reason', 'policy_denied'),
      );
      expect(
        result.terminalStep['trace_event'],
        containsPair('status', 'policy_denied'),
      );
    },
  );

  test(
    'AgentRuntimeNativeStepRunner fails when effect budget is exhausted',
    () async {
      final dispatcher = _RecordingDispatcher();
      final runner = AgentRuntimeNativeStepRunner(
        bridge: _FakeBridge(
          step: const <String, Object?>{
            'protocol_version': 'agent.v1',
            'run_id': 'run_1',
            'agent_id': 'execution_review',
            'status': 'effect_requested',
            'effect': <String, Object?>{
              'kind': 'tool',
              'effect_id': 'call_1',
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
        maxEffectSteps: 0,
      );

      expect(result['status'], 'closed_early');
      expect(result['error'], containsPair('code', 'effect_budget_exhausted'));
      expect(dispatcher.calls, isEmpty);
    },
  );

  test(
    'AgentRuntimeNativeStepRunner trace marks exhausted effect budgets',
    () async {
      final dispatcher = _RecordingDispatcher();
      final bridge = _FakeBridge(
        step: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': 'execution_review',
          'status': 'effect_requested',
          'effect': <String, Object?>{
            'kind': 'tool',
            'effect_id': 'call_1',
            'name': 'read_task',
            'input': <String, Object?>{'id': 'task_1'},
          },
        },
      );
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      );

      final result = await runner.runUntilTerminalWithTrace(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
        maxEffectSteps: 0,
      );

      expect(result.terminalStep['status'], 'closed_early');
      expect(result.dispatchedEffectCount, 0);
      expect(result.budgetExhausted, isTrue);
      expect(result.steps, hasLength(2));
      expect(result.effectResponses, isEmpty);
      expect(bridge.continuations, hasLength(1));
      expect(
        bridge.continuations.single.effectResponse,
        containsPair('jsonrpc', '2.0'),
      );
      expect(
        bridge.continuations.single.effectResponse,
        containsPair('id', 'call_1'),
      );
      expect(
        (bridge.continuations.single.effectResponse['result'] as Map)['error'],
        containsPair('code', 'effect_budget_exhausted'),
      );
      expect(
        result.terminalStep['run_state'],
        containsPair('status', 'closed_early'),
      );
      expect(
        result.terminalStep['run_state'],
        containsPair('terminal_reason', 'closed_early'),
      );
      expect(
        result.terminalStep['run_state'],
        containsPair('effect_result_count', 0),
      );
      expect(
        result.terminalStep['trace_event'],
        containsPair('status', 'closed_early'),
      );
      expect(
        result.terminalStep['trace_event'],
        containsPair('tool_name', 'read_task'),
      );
      expect(
        result.terminalStep['trace_event'],
        containsPair('run_state', result.terminalStep['run_state']),
      );
      expect(result.nativeTraceEvents, hasLength(1));
      expect(
        result.nativeTraceEvents.single,
        result.terminalStep['trace_event'],
      );
    },
  );

  test(
    'AgentRuntimeNativeStepRunner closed-early trace validates through bridge',
    () async {
      final bridge = _TraceValidatingBridge(
        step: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_budget',
          'agent_id': 'execution_review',
          'step_index': 0,
          'status': 'effect_requested',
          'effect': <String, Object?>{
            'kind': 'tool',
            'effect_id': 'call_1',
            'name': 'read_task',
            'input': <String, Object?>{'id': 'task_1'},
          },
          'run_state': <String, Object?>{
            'status': 'effect_requested',
            'step_index': 0,
            'remaining_effect_count': 1,
            'effect_result_count': 0,
            'terminal_reason': null,
          },
        },
      );
      final runner = AgentRuntimeNativeStepRunner(
        bridge: bridge,
        toolHost: AgentRuntimeToolHost(dispatcher: _RecordingDispatcher()),
      );

      final result = await runner.runUntilTerminalWithTrace(
        catalog: const <String, Object?>{'protocol_version': 'agent.v1'},
        request: const <String, Object?>{'input': <String, Object?>{}},
        agentId: 'execution_review',
        maxEffectSteps: 0,
      );
      final trace = <String, Object?>{
        'protocol_version': 'agent.v1',
        'runtime_version': '0.1.0',
        'run_id': 'run_budget',
        'agent_id': 'execution_review',
        'agent_version': '0.1.0',
        'started_at': '2026-06-28T09:12:31Z',
        'finished_at': '2026-06-28T09:12:32Z',
        'input': const <String, Object?>{},
        'output': result.terminalStep['error'],
        'events': <Object?>[
          const <String, Object?>{
            'kind': 'run_started',
            'occurred_at': '2026-06-28T09:12:31Z',
            'payload': <String, Object?>{'agent_id': 'execution_review'},
          },
          <String, Object?>{
            'kind': 'agent_runtime_step',
            'occurred_at': '2026-06-28T09:12:32Z',
            'payload': result.terminalStep['trace_event'],
          },
        ],
      };

      final normalized = await bridge.validateTrace(trace);

      expect(bridge.validatedTraces, hasLength(1));
      expect(
        normalized['events'],
        contains(
          containsPair('payload', containsPair('status', 'closed_early')),
        ),
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

      final result = await runner.startAndDispatchFirstEffectStep(
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
    required String effectResponseJson,
    required String agentId,
  }) async {
    final effectResponse =
        jsonDecode(effectResponseJson) as Map<String, Object?>;
    return jsonEncode(<String, Object?>{
      'protocol_version': 'agent.v1',
      'agent_id': agentId,
      'status': effectResponse['error'] == null ? 'completed' : 'failed',
      'output': <String, Object?>{'effect_result': effectResponse['result']},
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
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) async {
    continuations.add(_Continuation(previousStep, effectResponse));
    if (continuations.length <= _continuationSteps.length) {
      return _continuationSteps[continuations.length - 1];
    }
    final responseResult = effectResponse['result'];
    final error = responseResult is Map ? responseResult['error'] : null;
    if (error is Map && error['code'] == 'effect_budget_exhausted') {
      final stepIndex = previousStep['step_index'] ?? 0;
      final runState = <String, Object?>{
        'status': 'closed_early',
        'step_index': stepIndex,
        'remaining_effect_count': 0,
        'effect_result_count': error['dispatched_effect_count'] ?? 0,
        'terminal_reason': 'closed_early',
      };
      return <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': previousStep['run_id'],
        'agent_id': agentId,
        'step_index': stepIndex,
        'status': 'closed_early',
        'effect': previousStep['effect'],
        'effect_response': effectResponse,
        'effect_results': const <Object?>[],
        'run_state': runState,
        'trace_event': <String, Object?>{
          'kind': 'agent_runtime_step',
          'run_id': previousStep['run_id'],
          'agent_id': agentId,
          'status': 'closed_early',
          'step_index': stepIndex,
          'effect_id': (previousStep['effect'] as Map?)?['effect_id'],
          'effect_kind': (previousStep['effect'] as Map?)?['kind'],
          'tool_name': (previousStep['effect'] as Map?)?['name'],
          'subagent_id': null,
          'run_state': runState,
        },
        'error': error.map((key, value) => MapEntry(key.toString(), value)),
      };
    }
    final result = effectResponse['result'];
    if (result is Map) {
      final resultError = result['error'];
      final code = resultError is Map ? resultError['code'] : result['code'];
      if (code == 'policy_denied') {
        final stepIndex = previousStep['step_index'] ?? 1;
        final errorPayload = resultError is Map
            ? resultError.map((key, value) => MapEntry(key.toString(), value))
            : <String, Object?>{'code': 'policy_denied'};
        final runState = <String, Object?>{
          'status': 'policy_denied',
          'step_index': stepIndex,
          'remaining_effect_count': 0,
          'effect_result_count': 1,
          'terminal_reason': 'policy_denied',
        };
        return <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': previousStep['run_id'],
          'agent_id': agentId,
          'step_index': stepIndex,
          'status': 'policy_denied',
          'effect': previousStep['effect'],
          'effect_response': effectResponse,
          'effect_results': <Object?>[
            <String, Object?>{
              'effect': previousStep['effect'],
              'effect_response': effectResponse,
            },
          ],
          'run_state': runState,
          'trace_event': <String, Object?>{
            'kind': 'agent_runtime_step',
            'run_id': previousStep['run_id'],
            'agent_id': agentId,
            'status': 'policy_denied',
            'step_index': stepIndex,
            'effect_id': (previousStep['effect'] as Map?)?['effect_id'],
            'effect_kind': (previousStep['effect'] as Map?)?['kind'],
            'tool_name': (previousStep['effect'] as Map?)?['name'],
            'subagent_id': null,
            'run_state': runState,
          },
          'error': errorPayload,
        };
      }
    }
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'status': effectResponse['error'] == null ? 'completed' : 'failed',
      'effect': previousStep['effect'],
      'output': <String, Object?>{
        'mode': 'fake_continue',
        'effect_result': effectResponse['result'],
      },
    };
  }
}

class _TraceValidatingBridge extends _FakeBridge {
  _TraceValidatingBridge({required super.step});

  final validatedTraces = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    validatedTraces.add(trace);
    final runId = trace['run_id'];
    final agentId = trace['agent_id'];
    final events = trace['events'];
    expect(events, isA<List<Object?>>());
    final stepEvents = (events! as List<Object?>)
        .whereType<Map<String, Object?>>()
        .where((event) => event['kind'] == 'agent_runtime_step')
        .toList(growable: false);
    expect(stepEvents, isNotEmpty);
    for (final event in stepEvents) {
      final payload = event['payload']! as Map<String, Object?>;
      final runState = payload['run_state']! as Map<String, Object?>;
      expect(payload['run_id'], runId);
      expect(payload['agent_id'], agentId);
      expect(payload['status'], runState['status']);
      expect(payload['step_index'], runState['step_index']);
      expect(payload['effect_id'], isA<String>());
      expect(payload['effect_kind'], 'tool');
      expect(payload['tool_name'], isA<String>());
      expect(payload['subagent_id'], isNull);
      if (payload['status'] == 'closed_early') {
        expect(runState['terminal_reason'], 'closed_early');
        expect(runState['remaining_effect_count'], 0);
      }
    }
    return trace;
  }
}

class _EffectPlanBridge extends _FakeBridge {
  _EffectPlanBridge()
    : super(
        step: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': 'run_1',
          'agent_id': 'execution_review',
          'status': 'effect_requested',
          'effect': <String, Object?>{
            'kind': 'tool',
            'effect_id': 'call_1',
            'name': 'read_first',
            'input': <String, Object?>{'id': 'first'},
          },
          'continuation': <String, Object?>{
            'effects': <Object?>[
              <String, Object?>{
                'kind': 'tool',
                'name': 'read_second',
                'input': <String, Object?>{'id': 'second'},
              },
            ],
            'effect_results': <Object?>[],
          },
        },
      );

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) async {
    continuations.add(_Continuation(previousStep, effectResponse));
    final continuation = previousStep['continuation'];
    if (continuation is Map<String, Object?>) {
      final plan = continuation['effects'];
      if (plan is List<Object?> && plan.isNotEmpty) {
        final nextTool = plan.first! as Map<String, Object?>;
        return <String, Object?>{
          'protocol_version': 'agent.v1',
          'run_id': previousStep['run_id'],
          'agent_id': agentId,
          'status': 'effect_requested',
          'effect': <String, Object?>{
            'kind': 'tool',
            'effect_id': 'call_2',
            'name': nextTool['name'],
            'input': nextTool['input'],
          },
          'continuation': <String, Object?>{
            'effects': const <Object?>[],
            'effect_results': <Object?>[
              <String, Object?>{
                'effect': previousStep['effect'],
                'effect_response': effectResponse,
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
        'mode': 'frb_effect_loop',
        'effect_result': effectResponse['result'],
      },
    };
  }
}

class _SubagentBridge extends _FakeBridge {
  _SubagentBridge();

  final startedAgents = <String>[];
  final startedRequests = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    startedAgents.add(agentId);
    startedRequests.add(request);
    if (agentId == 'parent') {
      return const <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': 'parent_run',
        'agent_id': 'parent',
        'step_index': 0,
        'status': 'effect_requested',
        'effect': <String, Object?>{
          'kind': 'subagent',
          'effect_id': 'subagent_1',
          'agent_id': 'child',
          'run_id': 'child_run',
          'input': <String, Object?>{'from': 'parent'},
          'metadata': <String, Object?>{'surface': 'test'},
        },
      };
    }
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': request['run_id'] ?? 'generated_child_run',
      'agent_id': agentId,
      'step_index': 0,
      'status': 'completed',
      'output': <String, Object?>{
        'child_input': request['input'],
        'metadata': request['metadata'],
      },
    };
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) async {
    continuations.add(_Continuation(previousStep, effectResponse));
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'step_index': 1,
      'status': 'completed',
      'effect': previousStep['effect'],
      'effect_response': effectResponse,
      'output': <String, Object?>{'effect_result': effectResponse['result']},
    };
  }
}

class _SubagentBudgetBridge extends _SubagentBridge {
  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    startedAgents.add(agentId);
    startedRequests.add(request);
    if (agentId == 'parent') {
      return const <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': 'parent_run',
        'agent_id': 'parent',
        'step_index': 0,
        'status': 'effect_requested',
        'effect': <String, Object?>{
          'kind': 'subagent',
          'effect_id': 'subagent_1',
          'agent_id': 'child',
          'run_id': 'child_run',
          'input': <String, Object?>{'from': 'parent'},
        },
      };
    }
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': request['run_id'] ?? 'child_run',
      'agent_id': agentId,
      'step_index': 0,
      'status': 'effect_requested',
      'effect': const <String, Object?>{
        'kind': 'tool',
        'effect_id': 'child_tool_1',
        'name': 'read_child',
        'input': <String, Object?>{'id': 'child'},
      },
    };
  }
}

class _RecordingDispatcher implements DeviceToolDispatcher {
  _RecordingDispatcher({this.output});

  final Object? output;
  final calls = <_ToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(_ToolCall(name, input));
    return output ?? <String, Object?>{'tool': name, 'input': input};
  }
}

class _ToolCall {
  const _ToolCall(this.name, this.input);

  final String name;
  final Object? input;
}

class _Continuation {
  const _Continuation(this.previousStep, this.effectResponse);

  final Map<String, Object?> previousStep;
  final Map<String, Object?> effectResponse;
}
