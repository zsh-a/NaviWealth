library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_checkpoint_store.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_dispatcher.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_protocol.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/providers.dart';

export 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_step_result.dart'
    show AgentRuntimeNativeStepRunResult;

final agentRuntimeNativeStepRunnerProvider =
    Provider<AgentRuntimeNativeStepRunner>((ref) {
      return AgentRuntimeNativeStepRunner(
        bridge: ref.watch(agentRuntimeNativeBridgeProvider),
        toolHost: ref.watch(agentRuntimeToolHostProvider),
        checkpointStore: DriftAgentRuntimeCheckpointStore(
          databaseReader: () => ref.read(appDatabaseProvider.future),
          ownerUserIdReader: ref.watch(currentUserIdProvider),
        ),
      );
    });

class AgentRuntimeNativeStepRunner implements AgentRuntimeEffectStepRunner {
  AgentRuntimeNativeStepRunner({
    required AgentRuntimeNativeBridge bridge,
    required AgentRuntimeToolHost toolHost,
    AgentRuntimeCheckpointStore? checkpointStore,
    int defaultMaxEffectSteps = 4,
    int defaultMaxSubagentDepth = 4,
  }) : _bridge = bridge,
       _toolDispatcher = AgentRuntimeToolDispatcher(
         handler: toolHost.handleLine,
       ),
       _checkpointStore = checkpointStore,
       _defaultMaxEffectSteps = defaultMaxEffectSteps,
       _defaultMaxSubagentDepth = defaultMaxSubagentDepth;

  final AgentRuntimeNativeBridge _bridge;
  final AgentRuntimeToolDispatcher _toolDispatcher;
  final AgentRuntimeCheckpointStore? _checkpointStore;
  final int _defaultMaxEffectSteps;
  final int _defaultMaxSubagentDepth;

  AgentRuntimeNativeBridge get bridge => _bridge;
  int get defaultMaxEffectSteps => _defaultMaxEffectSteps;
  int get defaultMaxSubagentDepth => _defaultMaxSubagentDepth;

  Future<Map<String, Object?>> startAndDispatchFirstEffectStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) {
    return runUntilTerminal(
      catalog: catalog,
      request: request,
      agentId: agentId,
      maxEffectSteps: 1,
    );
  }

  Future<Map<String, Object?>> runUntilTerminal({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxEffectSteps,
  }) async {
    return (await runUntilTerminalWithTrace(
      catalog: catalog,
      request: request,
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
    )).terminalStep;
  }

  @override
  Future<AgentRuntimeNativeStepRunResult> runUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxEffectSteps,
  }) async {
    final limit = maxEffectSteps ?? _defaultMaxEffectSteps;
    if (limit < 0) {
      throw RangeError.value(limit, 'maxEffectSteps', 'must be non-negative');
    }
    final bridge = _bridge;
    if (bridge is AgentRuntimeSnapshotBridge) {
      final snapshotBridge = bridge as AgentRuntimeSnapshotBridge;
      final requestFingerprint = agentRuntimeRequestFingerprint(
        agentId: agentId,
        catalog: catalog,
        request: request,
      );
      final checkpoint = await _checkpointStore?.findResumable(
        agentId: agentId,
        requestFingerprint: requestFingerprint,
      );
      final execution = await _runSnapshotUntilTerminal(
        bridge: snapshotBridge,
        catalog: catalog,
        initialSnapshot:
            checkpoint?.snapshot ??
            await snapshotBridge.startRunSnapshot(
              catalog: catalog,
              request: request,
              agentId: agentId,
              maxEffectSteps: limit,
              maxSubagentDepth: _defaultMaxSubagentDepth,
            ),
        agentId: agentId,
        requestFingerprint: requestFingerprint,
        initialCheckpoint: checkpoint,
      );
      return execution.result;
    }
    final step = await _bridge.startRunStep(
      catalog: catalog,
      request: request,
      agentId: agentId,
    );
    return continueUntilTerminalWithTrace(
      catalog: catalog,
      initialStep: step,
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
    );
  }

  Future<_SnapshotExecution> _runSnapshotUntilTerminal({
    required AgentRuntimeSnapshotBridge bridge,
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialSnapshot,
    required String agentId,
    required String requestFingerprint,
    Map<String, Object?> resumeContext = const <String, Object?>{},
    AgentRuntimeCheckpoint? initialCheckpoint,
  }) async {
    var checkpoint = initialCheckpoint;
    var snapshot = checkpoint?.snapshot ?? initialSnapshot;
    final checkpointStore = _checkpointStore;
    if (checkpointStore != null) {
      checkpoint ??= await checkpointStore.create(
        requestFingerprint: requestFingerprint,
        snapshot: snapshot,
        resumeContext: resumeContext,
      );
      if (checkpoint.requestFingerprint != requestFingerprint ||
          checkpoint.agentId != agentId) {
        throw const AgentRuntimeCheckpointException(
          AgentRuntimeCheckpointErrorCode.corrupt,
          'resumable checkpoint identity does not match the requested run',
        );
      }
      snapshot = checkpoint.snapshot;
      resumeContext = checkpoint.resumeContext;
    }
    var step = _snapshotStep(snapshot);
    final steps = <Map<String, Object?>>[step];
    final effectResponses = <Map<String, Object?>>[];

    while (_isHostEffectRequested(step)) {
      final effect = agentRuntimeObject(
        step['effect'],
        label: 'native agent-runtime effect',
      );
      final effectId = agentRuntimeString(effect['effect_id']);
      final effectKind = agentRuntimeString(effect['kind']);
      if (effectId.isEmpty) {
        throw const FormatException('native effect.effect_id is required');
      }
      switch (effect['kind']) {
        case 'tool':
          final recorded = checkpointStore == null
              ? _RecordedCheckpointEffect(
                  checkpoint: null,
                  payload: await _dispatchToolCall(step),
                )
              : await _recordCheckpointEffect(
                  checkpointStore: checkpointStore,
                  checkpoint: checkpoint!,
                  effectKind: effectKind,
                  effectId: effectId,
                  dispatch: () => _dispatchToolCall(step),
                );
          checkpoint = recorded.checkpoint;
          final response = recorded.payload;
          effectResponses.add(response);
          snapshot = await bridge.continueRunSnapshot(
            catalog: catalog,
            snapshot: snapshot,
            effectResponse: response,
            agentId: agentId,
          );
        case 'subagent':
          final subagentId = agentRuntimeString(effect['agent_id']);
          if (subagentId.isEmpty) {
            throw const FormatException('native effect.agent_id is required');
          }
          final recorded = checkpointStore == null
              ? _RecordedCheckpointEffect(
                  checkpoint: null,
                  payload: <String, Object?>{
                    'child_snapshot': (await _runSnapshotUntilTerminal(
                      bridge: bridge,
                      catalog: catalog,
                      initialSnapshot: await bridge
                          .startRequestedSubagentSnapshot(
                            catalog: catalog,
                            parentSnapshot: snapshot,
                          ),
                      agentId: subagentId,
                      requestFingerprint: _subagentRequestFingerprint(
                        parentFingerprint: requestFingerprint,
                        effectId: effectId,
                        subagentId: subagentId,
                      ),
                    )).snapshot,
                  },
                )
              : await _recordCheckpointEffect(
                  checkpointStore: checkpointStore,
                  checkpoint: checkpoint!,
                  effectKind: effectKind,
                  effectId: effectId,
                  dispatch: () async {
                    final child = await _runSnapshotUntilTerminal(
                      bridge: bridge,
                      catalog: catalog,
                      initialSnapshot: await bridge
                          .startRequestedSubagentSnapshot(
                            catalog: catalog,
                            parentSnapshot: snapshot,
                          ),
                      agentId: subagentId,
                      requestFingerprint: _subagentRequestFingerprint(
                        parentFingerprint: requestFingerprint,
                        effectId: effectId,
                        subagentId: subagentId,
                      ),
                    );
                    return <String, Object?>{'child_snapshot': child.snapshot};
                  },
                );
          checkpoint = recorded.checkpoint;
          final childSnapshot = agentRuntimeObject(
            recorded.payload['child_snapshot'],
            label: 'recorded subagent snapshot',
          );
          snapshot = await bridge.resumeParentFromSubagentSnapshot(
            catalog: catalog,
            parentSnapshot: snapshot,
            childSnapshot: childSnapshot,
          );
        default:
          throw FormatException(
            'native agent-runtime effect kind is unsupported',
            effect['kind'],
          );
      }
      if (checkpointStore != null) {
        checkpoint = await checkpointStore.replaceSnapshot(
          runId: checkpoint!.runId,
          expectedRevision: checkpoint.revision,
          requestFingerprint: requestFingerprint,
          snapshot: snapshot,
          resumeContext: resumeContext,
        );
      }
      step = _snapshotStep(snapshot);
      steps.add(step);
    }

    final limits = agentRuntimeObject(
      snapshot['limits'],
      label: 'native agent-runtime snapshot limits',
    );
    final progress = agentRuntimeObject(
      snapshot['progress'],
      label: 'native agent-runtime snapshot progress',
    );
    final maxEffectSteps = _snapshotInt(limits, 'max_effect_steps');
    final dispatchedEffectCount = _snapshotInt(
      progress,
      'dispatched_effect_count',
    );
    final result = AgentRuntimeNativeStepRunResult(
      terminalStep: step,
      steps: steps,
      effectResponses: effectResponses,
      nativeTraceEvents: _nativeTraceEvents(steps),
      dispatchedEffectCount: dispatchedEffectCount,
      budgetExhausted: progress['effect_budget_exhausted'] == true,
      maxEffectSteps: maxEffectSteps,
      remainingEffectSteps: (maxEffectSteps - dispatchedEffectCount).clamp(
        0,
        maxEffectSteps,
      ),
      maxSubagentDepth: _snapshotInt(limits, 'max_subagent_depth'),
      subagentDepthExceeded: progress['subagent_depth_exceeded'] == true,
      terminalSnapshot: snapshot,
    );
    return _SnapshotExecution(snapshot: snapshot, result: result);
  }

  Future<AgentRuntimeNativeStepRunResult>
  continueSnapshotUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialSnapshot,
    required String agentId,
    String? requestFingerprint,
    Map<String, Object?> resumeContext = const <String, Object?>{},
  }) async {
    final bridge = _bridge;
    if (bridge is! AgentRuntimeSnapshotBridge) {
      throw UnsupportedError('native runtime does not expose snapshot APIs');
    }
    return (await _runSnapshotUntilTerminal(
      bridge: bridge as AgentRuntimeSnapshotBridge,
      catalog: catalog,
      initialSnapshot: initialSnapshot,
      agentId: agentId,
      requestFingerprint:
          requestFingerprint ??
          agentRuntimeRequestFingerprint(
            agentId: agentId,
            catalog: catalog,
            kind: 'snapshot_resume',
            request: <String, Object?>{
              'run_id': _snapshotRunId(initialSnapshot),
            },
          ),
      resumeContext: resumeContext,
    )).result;
  }

  Future<AgentRuntimeCheckpoint?> findResumableCheckpoint({
    required String agentId,
    required String requestFingerprint,
  }) {
    final store = _checkpointStore;
    if (store == null) return Future<AgentRuntimeCheckpoint?>.value();
    return store.findResumable(
      agentId: agentId,
      requestFingerprint: requestFingerprint,
    );
  }

  Future<AgentRuntimeNativeStepRunResult> continueCheckpointUntilTerminal({
    required Map<String, Object?> catalog,
    required AgentRuntimeCheckpoint checkpoint,
  }) async {
    final bridge = _bridge;
    if (bridge is! AgentRuntimeSnapshotBridge) {
      throw UnsupportedError('native runtime does not expose snapshot APIs');
    }
    return (await _runSnapshotUntilTerminal(
      bridge: bridge as AgentRuntimeSnapshotBridge,
      catalog: catalog,
      initialSnapshot: checkpoint.snapshot,
      agentId: checkpoint.agentId,
      requestFingerprint: checkpoint.requestFingerprint,
      resumeContext: checkpoint.resumeContext,
      initialCheckpoint: checkpoint,
    )).result;
  }

  Future<AgentRuntimeNativeStepRunResult> cancelCheckpoint({
    required Map<String, Object?> catalog,
    required AgentRuntimeCheckpoint checkpoint,
    required String reason,
  }) async {
    final bridge = _bridge;
    if (bridge is! AgentRuntimeSnapshotBridge ||
        bridge is! AgentRuntimeSnapshotControlBridge) {
      throw UnsupportedError(
        'native runtime does not expose snapshot cancellation APIs',
      );
    }
    var cancelledSnapshot = await (bridge as AgentRuntimeSnapshotControlBridge)
        .cancelRunSnapshot(
          catalog: catalog,
          snapshot: checkpoint.snapshot,
          agentId: checkpoint.agentId,
          reason: reason,
        );
    var cancelledCheckpoint = checkpoint;
    final checkpointStore = _checkpointStore;
    if (checkpointStore != null) {
      cancelledCheckpoint = await checkpointStore.replaceSnapshot(
        runId: checkpoint.runId,
        expectedRevision: checkpoint.revision,
        requestFingerprint: checkpoint.requestFingerprint,
        snapshot: cancelledSnapshot,
        resumeContext: checkpoint.resumeContext,
      );
      cancelledSnapshot = cancelledCheckpoint.snapshot;
    }
    return (await _runSnapshotUntilTerminal(
      bridge: bridge as AgentRuntimeSnapshotBridge,
      catalog: catalog,
      initialSnapshot: cancelledSnapshot,
      agentId: checkpoint.agentId,
      requestFingerprint: checkpoint.requestFingerprint,
      resumeContext: checkpoint.resumeContext,
      initialCheckpoint: checkpointStore == null ? null : cancelledCheckpoint,
    )).result;
  }

  Future<_RecordedCheckpointEffect> _recordCheckpointEffect({
    required AgentRuntimeCheckpointStore checkpointStore,
    required AgentRuntimeCheckpoint checkpoint,
    required String effectKind,
    required String effectId,
    required Future<Map<String, Object?>> Function() dispatch,
  }) async {
    switch (checkpoint.status) {
      case AgentRuntimeCheckpointStatus.awaitingEffect:
        checkpoint = await checkpointStore.reserveEffect(
          runId: checkpoint.runId,
          expectedRevision: checkpoint.revision,
          effectKind: effectKind,
          effectId: effectId,
        );
        final payload = await dispatch();
        checkpoint = await checkpointStore.recordEffectPayload(
          runId: checkpoint.runId,
          expectedRevision: checkpoint.revision,
          effectKind: effectKind,
          effectId: effectId,
          payload: payload,
        );
        return _RecordedCheckpointEffect(
          checkpoint: checkpoint,
          payload: payload,
        );
      case AgentRuntimeCheckpointStatus.effectRecorded:
        if (checkpoint.effectKind != effectKind ||
            checkpoint.effectId != effectId ||
            checkpoint.effectPayload == null) {
          throw const AgentRuntimeCheckpointException(
            AgentRuntimeCheckpointErrorCode.corrupt,
            'recorded checkpoint effect does not match the runtime snapshot',
          );
        }
        return _RecordedCheckpointEffect(
          checkpoint: checkpoint,
          payload: checkpoint.effectPayload!,
        );
      case AgentRuntimeCheckpointStatus.dispatching:
        throw AgentRuntimeCheckpointException(
          AgentRuntimeCheckpointErrorCode.interruptedEffect,
          'effect $effectId may have started before the app stopped; '
          'automatic redispatch is blocked',
        );
      case AgentRuntimeCheckpointStatus.terminal:
        throw const AgentRuntimeCheckpointException(
          AgentRuntimeCheckpointErrorCode.invalidTransition,
          'terminal checkpoint cannot dispatch an effect',
        );
    }
  }

  Future<Map<String, Object?>> continueUntilTerminal({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialStep,
    required String agentId,
    int? maxEffectSteps,
  }) async {
    return (await continueUntilTerminalWithTrace(
      catalog: catalog,
      initialStep: initialStep,
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
    )).terminalStep;
  }

  Future<AgentRuntimeNativeStepRunResult> continueUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialStep,
    required String agentId,
    int? maxEffectSteps,
  }) async {
    final limit = maxEffectSteps ?? _defaultMaxEffectSteps;
    if (limit < 0) {
      throw RangeError.value(limit, 'maxEffectSteps', 'must be non-negative');
    }
    final budget = _EffectRunBudget(limit);
    return _continueUntilTerminalWithTrace(
      catalog: catalog,
      initialStep: initialStep,
      agentId: agentId,
      budget: budget,
      depth: 0,
    );
  }

  Future<AgentRuntimeNativeStepRunResult> _continueUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialStep,
    required String agentId,
    required _EffectRunBudget budget,
    required int depth,
  }) async {
    var step = initialStep;
    final steps = <Map<String, Object?>>[step];
    final effectResponses = <Map<String, Object?>>[];
    var subagentDepthExceeded = false;

    while (_isHostEffectRequested(step)) {
      if (!budget.canDispatch) {
        budget.markExhausted();
        step = await _bridge.continueRunStep(
          catalog: catalog,
          previousStep: step,
          effectResponse: agentRuntimeEffectBudgetExhaustedResponse(
            effectId: _effectId(
              agentRuntimeObject(
                step['effect'],
                label: 'native agent-runtime effect',
              ),
              step,
            ),
            maxEffectSteps: budget.max,
            dispatchedEffectCount: budget.dispatched,
          ),
          agentId: agentId,
        );
        steps.add(step);
        return AgentRuntimeNativeStepRunResult(
          terminalStep: step,
          steps: steps,
          effectResponses: effectResponses,
          nativeTraceEvents: _nativeTraceEvents(steps),
          dispatchedEffectCount: budget.dispatched,
          budgetExhausted: true,
          maxEffectSteps: budget.max,
          remainingEffectSteps: budget.remaining,
          maxSubagentDepth: _defaultMaxSubagentDepth,
          subagentDepthExceeded: subagentDepthExceeded,
        );
      }
      budget.markDispatched();

      final dispatch = await _dispatchHostEffect(
        step: step,
        catalog: catalog,
        budget: budget,
        depth: depth,
      );
      subagentDepthExceeded =
          subagentDepthExceeded || dispatch.subagentDepthExceeded;
      final response = dispatch.response;
      effectResponses.add(response);
      step = await _bridge.continueRunStep(
        catalog: catalog,
        previousStep: step,
        effectResponse: response,
        agentId: agentId,
      );
      steps.add(step);
    }

    return AgentRuntimeNativeStepRunResult(
      terminalStep: step,
      steps: steps,
      effectResponses: effectResponses,
      nativeTraceEvents: _nativeTraceEvents(steps),
      dispatchedEffectCount: budget.dispatched,
      budgetExhausted: budget.exhausted,
      maxEffectSteps: budget.max,
      remainingEffectSteps: budget.remaining,
      maxSubagentDepth: _defaultMaxSubagentDepth,
      subagentDepthExceeded: subagentDepthExceeded,
    );
  }

  Future<Map<String, Object?>> _dispatchToolCall(
    Map<String, Object?> step,
  ) async {
    final effect = agentRuntimeObject(
      step['effect'],
      label: 'native agent-runtime effect',
    );
    final name = effect['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('native effect.name is required');
    }

    return (await _toolDispatcher.call(
      AgentRuntimeToolCall(
        id: _effectId(effect, step),
        name: name,
        input: effect['input'],
      ),
    )).response;
  }

  Future<_HostEffectDispatch> _dispatchHostEffect({
    required Map<String, Object?> step,
    required Map<String, Object?> catalog,
    required _EffectRunBudget budget,
    required int depth,
  }) async {
    if (step['status'] != 'effect_requested') {
      throw FormatException(
        'native agent-runtime host effect status is unsupported',
        step['status'],
      );
    }
    final effect = agentRuntimeObject(
      step['effect'],
      label: 'native agent-runtime effect',
    );
    return switch (effect['kind']) {
      'tool' => _dispatchToolCall(
        step,
      ).then((response) => _HostEffectDispatch(response)),
      'subagent' => _dispatchSubagent(
        step: step,
        catalog: catalog,
        budget: budget,
        depth: depth,
      ),
      _ => throw FormatException(
        'native agent-runtime effect kind is unsupported',
        effect['kind'],
      ),
    };
  }

  Future<_HostEffectDispatch> _dispatchSubagent({
    required Map<String, Object?> step,
    required Map<String, Object?> catalog,
    required _EffectRunBudget budget,
    required int depth,
  }) async {
    final subagentCall = agentRuntimeObject(
      step['effect'],
      label: 'native agent-runtime effect',
    );
    final subagentId = agentRuntimeString(subagentCall['agent_id']);
    if (subagentId.isEmpty) {
      throw const FormatException('native effect.agent_id is required');
    }
    final id = _effectId(subagentCall, step);
    if (depth >= _defaultMaxSubagentDepth) {
      return _HostEffectDispatch(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{
          'error': <String, Object?>{
            'code': 'subagent_depth_exceeded',
            'message':
                'subagent depth exceeded '
                '($_defaultMaxSubagentDepth)',
          },
        },
      }, subagentDepthExceeded: true);
    }
    try {
      final childRun = await _continueUntilTerminalWithTrace(
        catalog: catalog,
        initialStep: await _bridge.startRunStep(
          catalog: catalog,
          request: _subagentRunRequest(subagentCall),
          agentId: subagentId,
        ),
        agentId: subagentId,
        budget: budget,
        depth: depth + 1,
      );
      return _HostEffectDispatch(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{
          'agent_id': subagentId,
          'terminal_step': childRun.terminalStep,
          'steps': childRun.steps,
          'effect_responses': childRun.effectResponses,
          'native_trace_events': childRun.nativeTraceEvents,
          'dispatched_effect_count': childRun.dispatchedEffectCount,
          'budget_exhausted': childRun.budgetExhausted,
          'max_effect_steps': childRun.maxEffectSteps,
          'remaining_effect_steps': childRun.remainingEffectSteps,
          'max_subagent_depth': childRun.maxSubagentDepth,
          'subagent_depth_exceeded': childRun.subagentDepthExceeded,
        },
      }, subagentDepthExceeded: childRun.subagentDepthExceeded);
    } catch (error) {
      return _HostEffectDispatch(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{
          'error': <String, Object?>{
            'code': 'subagent_run_failed',
            'message': error.toString(),
          },
        },
      });
    }
  }
}

class _EffectRunBudget {
  _EffectRunBudget(this.max) : remaining = max;

  final int max;
  int remaining;
  bool exhausted = false;

  int get dispatched => max - remaining;

  bool get canDispatch => remaining > 0;

  void markDispatched() {
    remaining -= 1;
  }

  void markExhausted() {
    exhausted = true;
  }
}

class _HostEffectDispatch {
  const _HostEffectDispatch(
    this.response, {
    this.subagentDepthExceeded = false,
  });

  final Map<String, Object?> response;
  final bool subagentDepthExceeded;
}

class _SnapshotExecution {
  const _SnapshotExecution({required this.snapshot, required this.result});

  final Map<String, Object?> snapshot;
  final AgentRuntimeNativeStepRunResult result;
}

class _RecordedCheckpointEffect {
  const _RecordedCheckpointEffect({
    required this.checkpoint,
    required this.payload,
  });

  final AgentRuntimeCheckpoint? checkpoint;
  final Map<String, Object?> payload;
}

bool _isHostEffectRequested(Map<String, Object?> step) {
  return switch (step['status']) {
    'effect_requested' => true,
    _ => false,
  };
}

List<Map<String, Object?>> _nativeTraceEvents(
  Iterable<Map<String, Object?>> steps,
) {
  return [
    for (final step in steps) ?agentRuntimeObjectOrNull(step['trace_event']),
  ];
}

Map<String, Object?> _snapshotStep(Map<String, Object?> snapshot) {
  return agentRuntimeObject(
    snapshot['step'],
    label: 'native agent-runtime snapshot step',
  );
}

int _snapshotInt(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is int && value >= 0) return value;
  throw FormatException(
    'native agent-runtime snapshot $field must be a non-negative integer',
    value,
  );
}

String _snapshotRunId(Map<String, Object?> snapshot) {
  final step = _snapshotStep(snapshot);
  final runId = agentRuntimeString(step['run_id']);
  if (runId.isEmpty) {
    throw const FormatException(
      'native agent-runtime snapshot step.run_id is required',
    );
  }
  return runId;
}

String _subagentRequestFingerprint({
  required String parentFingerprint,
  required String effectId,
  required String subagentId,
}) {
  return '$parentFingerprint/subagent/$effectId/$subagentId';
}

Object _effectId(Map<String, Object?> effect, Map<String, Object?> step) {
  final explicitId = effect['effect_id'];
  if (explicitId is String && explicitId.isNotEmpty) return explicitId;
  final runId = step['run_id'];
  if (runId is String && runId.isNotEmpty) return runId;
  return 'effect';
}

Map<String, Object?> _subagentRunRequest(Map<String, Object?> subagentCall) {
  final request = <String, Object?>{
    'protocol_version': kAgentRuntimeProtocolVersion,
    if (subagentCall['run_id'] case final String runId when runId.isNotEmpty)
      'run_id': runId,
    'input': _subagentInput(subagentCall['input']),
    'trigger': 'manual',
    'metadata':
        agentRuntimeObjectOrNull(subagentCall['metadata']) ??
        const <String, Object?>{},
  };
  final scope = agentRuntimeObjectOrNull(subagentCall['scope']);
  if (scope != null) request['scope'] = scope;
  final workflow = agentRuntimeObjectOrNull(subagentCall['workflow']);
  if (workflow != null) request['workflow'] = workflow;
  return request;
}

Map<String, Object?> _subagentInput(Object? input) {
  return agentRuntimeObjectOrNull(input) ?? <String, Object?>{'value': input};
}
