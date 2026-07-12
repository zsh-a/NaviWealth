import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_storage_policy.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_checkpoint_store.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';

void main() {
  test('FFI bridge initializes once and decodes snapshot responses', () async {
    final initCalls = <String?>[];
    final api = _FakeHostNativeApi();
    final bridge = FfiAgentRuntimeNativeBridge(
      api: api,
      libraryPath: '/tmp/liblifeos_native.dylib',
      initRuntime: ({String? libraryPath}) async {
        initCalls.add(libraryPath);
      },
    );

    expect(await bridge.protocolVersion(), 'agent.v1');
    expect(await bridge.catalogVersion(), 'agent_catalog.v1');
    expect(
      await bridge.catalogSummary(_catalog),
      containsPair('catalog_version', 'agent_catalog.v1'),
    );
    final snapshot = await bridge.startRunSnapshot(
      catalog: _catalog,
      request: _request,
      agentId: 'execution_review',
      maxEffectSteps: 3,
      maxSubagentDepth: 2,
    );

    expect(snapshot['step'], containsPair('status', 'completed'));
    expect(initCalls, ['/tmp/liblifeos_native.dylib']);
    expect(
      api.catalogPayloads.single,
      contains('"protocol_version":"agent.v1"'),
    );
  });

  test('storage policy defaults to app-owned persistence', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final policy = container.read(agentRuntimeStoragePolicyProvider);

    expect(policy.mode, AgentRuntimeStorageMode.appOwned);
    expect(policy.storePath, isNull);
  });

  test('snapshot runner dispatches tool and returns native progress', () async {
    final bridge = _FakeExecutionBridge();
    final dispatcher = _RecordingDispatcher(
      output: <String, Object?>{'ok': true},
    );
    final runner = AgentRuntimeNativeStepRunner(
      bridge: bridge,
      toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
    );

    final result = await runner.runUntilTerminalWithTrace(
      catalog: _catalog,
      request: _request,
      agentId: 'execution_review',
      maxEffectSteps: 3,
    );

    expect(bridge.startCount, 1);
    expect(bridge.continueCount, 1);
    expect(dispatcher.calls.single.name, 'read_snapshot');
    expect(result.terminalStep['status'], 'completed');
    expect(result.dispatchedEffectCount, 1);
    expect(result.remainingEffectSteps, 2);
    expect(result.steps, hasLength(2));
  });

  test('checkpoint resumes a recorded effect without redispatch', () async {
    final store = InMemoryAgentRuntimeCheckpointStore();
    final bridge = _FakeExecutionBridge(failFirstContinuation: true);
    final firstDispatcher = _RecordingDispatcher();
    final firstRunner = AgentRuntimeNativeStepRunner(
      bridge: bridge,
      toolHost: AgentRuntimeToolHost(dispatcher: firstDispatcher),
      checkpointStore: store,
    );

    await expectLater(
      firstRunner.runUntilTerminalWithTrace(
        catalog: _catalog,
        request: _request,
        agentId: 'execution_review',
      ),
      throwsStateError,
    );
    expect(firstDispatcher.calls, hasLength(1));

    final secondDispatcher = _RecordingDispatcher();
    final resumed =
        await AgentRuntimeNativeStepRunner(
          bridge: bridge,
          toolHost: AgentRuntimeToolHost(dispatcher: secondDispatcher),
          checkpointStore: store,
        ).runUntilTerminalWithTrace(
          catalog: _catalog,
          request: _request,
          agentId: 'execution_review',
        );

    expect(resumed.terminalStep['status'], 'completed');
    expect(secondDispatcher.calls, isEmpty);
    expect(bridge.startCount, 1);
    expect(bridge.continueCount, 1);
  });

  test('checkpoint cancellation is terminal and does not dispatch', () async {
    final store = InMemoryAgentRuntimeCheckpointStore();
    final bridge = _FakeExecutionBridge();
    final fingerprint = agentRuntimeRequestFingerprint(
      agentId: 'execution_review',
      catalog: _catalog,
      request: _request,
    );
    final checkpoint = await store.create(
      requestFingerprint: fingerprint,
      snapshot: await bridge.startRunSnapshot(
        catalog: _catalog,
        request: _request,
        agentId: 'execution_review',
        maxEffectSteps: 4,
        maxSubagentDepth: 4,
      ),
    );
    final dispatcher = _RecordingDispatcher();
    final runner = AgentRuntimeNativeStepRunner(
      bridge: bridge,
      toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
      checkpointStore: store,
    );

    final result = await runner.cancelCheckpoint(
      catalog: _catalog,
      checkpoint: checkpoint,
      reason: 'user stopped the run',
    );

    expect(result.terminalStep['status'], 'cancelled');
    expect(result.terminalStep['error'], containsPair('code', 'user_cancel'));
    expect(dispatcher.calls, isEmpty);
    expect(bridge.cancelCount, 1);
    expect(
      await store.findResumable(
        agentId: 'execution_review',
        requestFingerprint: fingerprint,
      ),
      isNull,
    );
  });

  test('FFI bridge rejects runtime-owned SQLite policy', () async {
    var initCalls = 0;
    final bridge = FfiAgentRuntimeNativeBridge(
      api: _FakeHostNativeApi(),
      initRuntime: ({String? libraryPath}) async {
        initCalls += 1;
      },
      storagePolicy: const AgentRuntimeStoragePolicy.runtimeOwnedSqliteDebug(
        storePath: '/tmp/runtime.sqlite',
      ),
    );

    await expectLater(bridge.protocolVersion(), throwsUnsupportedError);
    expect(initCalls, 0);
  });
}

const _catalog = <String, Object?>{
  'protocol_version': 'agent.v1',
  'catalog_version': 'agent_catalog.v1',
  'agents': <Object?>[],
  'tools': <Object?>[],
};

const _request = <String, Object?>{
  'protocol_version': 'agent.v1',
  'input': <String, Object?>{},
};

class _FakeHostNativeApi implements AgentRuntimeHostNativeApi {
  final catalogPayloads = <String>[];

  @override
  Future<String> protocolVersion() async => 'agent.v1';

  @override
  Future<String> catalogVersion() async => 'agent_catalog.v1';

  @override
  Future<String> catalogSummary({required String catalogJson}) async {
    catalogPayloads.add(catalogJson);
    return catalogJson;
  }

  @override
  Future<String> validateRunRequest({required String requestJson}) async =>
      requestJson;

  @override
  Future<String> validateTrace({required String traceJson}) async => traceJson;

  @override
  Future<String> validateToolSpec({required String toolJson}) async => toolJson;

  @override
  Future<String> validateLlmRequest({required String requestJson}) async =>
      requestJson;

  @override
  Future<String> validateLlmResponse({required String responseJson}) async =>
      responseJson;

  @override
  Future<String> completeMockLlm({
    required String requestJson,
    required String responseText,
  }) async => jsonEncode(<String, Object?>{'content': responseText});

  @override
  Future<String> completeProfileLlm({required String requestJson}) async =>
      jsonEncode(<String, Object?>{'content': 'profile answer'});

  @override
  Future<String> startRunSnapshot({
    required String catalogJson,
    required String requestJson,
    required String agentId,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async => jsonEncode(
    _terminalSnapshot(
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    ),
  );

  @override
  Future<String> startProfileTurnSnapshot({
    required String catalogJson,
    required String llmRequestJson,
    required String agentId,
    required String runMetadataJson,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async => jsonEncode(<String, Object?>{
    'protocol_version': 'agent.v1',
    'llm_response': <String, Object?>{'content': 'profile answer'},
    'snapshot': _terminalSnapshot(
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    ),
  });

  @override
  Future<String> continueRunSnapshot({
    required String catalogJson,
    required String snapshotJson,
    required String effectResponseJson,
    required String agentId,
  }) async => snapshotJson;

  @override
  Future<String> cancelRunSnapshot({
    required String catalogJson,
    required String snapshotJson,
    required String agentId,
    required String reason,
  }) async => snapshotJson;

  @override
  Future<String> startRequestedSubagentSnapshot({
    required String catalogJson,
    required String parentSnapshotJson,
  }) async => parentSnapshotJson;

  @override
  Future<String> resumeParentFromSubagentSnapshot({
    required String catalogJson,
    required String parentSnapshotJson,
    required String childSnapshotJson,
  }) async => parentSnapshotJson;
}

class _FakeExecutionBridge implements AgentRuntimeExecutionBridge {
  _FakeExecutionBridge({this.failFirstContinuation = false});

  bool failFirstContinuation;
  int startCount = 0;
  int continueCount = 0;
  int cancelCount = 0;

  @override
  Future<Map<String, Object?>> startRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async {
    startCount += 1;
    return _requestedSnapshot(
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    );
  }

  @override
  Future<Map<String, Object?>> startProfileTurnSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async => <String, Object?>{
    'protocol_version': 'agent.v1',
    'llm_response': <String, Object?>{'content': 'profile answer'},
    'snapshot': _requestedSnapshot(
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    ),
  };

  @override
  Future<Map<String, Object?>> continueRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) async {
    if (failFirstContinuation) {
      failFirstContinuation = false;
      throw StateError('simulated crash before snapshot replacement');
    }
    continueCount += 1;
    final limits = Map<String, Object?>.from(snapshot['limits']! as Map);
    return _terminalSnapshot(
      agentId: agentId,
      maxEffectSteps: limits['max_effect_steps']! as int,
      maxSubagentDepth: limits['max_subagent_depth']! as int,
      dispatchedEffectCount: 1,
      output: <String, Object?>{'effect_result': effectResponse['result']},
    );
  }

  @override
  Future<Map<String, Object?>> cancelRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required String agentId,
    required String reason,
  }) async {
    cancelCount += 1;
    final step = Map<String, Object?>.from(snapshot['step']! as Map);
    return <String, Object?>{
      ...snapshot,
      'step': <String, Object?>{
        ...step,
        'status': 'cancelled',
        'effect': null,
        'error': <String, Object?>{'code': 'user_cancel', 'message': reason},
      },
    };
  }

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
}

Map<String, Object?> _requestedSnapshot({
  required String agentId,
  required int maxEffectSteps,
  required int maxSubagentDepth,
}) => <String, Object?>{
  'protocol_version': 'agent.v1',
  'snapshot_version': 1,
  'step': <String, Object?>{
    'protocol_version': 'agent.v1',
    'run_id': 'snapshot_run',
    'agent_id': agentId,
    'step_index': 0,
    'status': 'effect_requested',
    'effect': const <String, Object?>{
      'kind': 'tool',
      'effect_id': 'snapshot_tool_1',
      'name': 'read_snapshot',
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
};

Map<String, Object?> _terminalSnapshot({
  required String agentId,
  required int maxEffectSteps,
  required int maxSubagentDepth,
  int dispatchedEffectCount = 0,
  Map<String, Object?> output = const <String, Object?>{},
}) => <String, Object?>{
  'protocol_version': 'agent.v1',
  'snapshot_version': 1,
  'step': <String, Object?>{
    'protocol_version': 'agent.v1',
    'run_id': 'snapshot_run',
    'agent_id': agentId,
    'step_index': dispatchedEffectCount,
    'status': 'completed',
    'output': output,
  },
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
