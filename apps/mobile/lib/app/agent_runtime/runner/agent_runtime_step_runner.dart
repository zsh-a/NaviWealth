library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_checkpoint_store.dart';
import 'package:naviwealth/app/agent_runtime/persistence/drift_agent_runtime_checkpoint_store.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_dispatcher.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';
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
    required AgentRuntimeExecutionBridge bridge,
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

  final AgentRuntimeExecutionBridge _bridge;
  final AgentRuntimeToolDispatcher _toolDispatcher;
  final AgentRuntimeCheckpointStore? _checkpointStore;
  final int _defaultMaxEffectSteps;
  final int _defaultMaxSubagentDepth;

  AgentRuntimeExecutionBridge get bridge => _bridge;
  int get defaultMaxEffectSteps => _defaultMaxEffectSteps;
  int get defaultMaxSubagentDepth => _defaultMaxSubagentDepth;

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
      bridge: _bridge,
      catalog: catalog,
      initialSnapshot:
          checkpoint?.snapshot ??
          await _bridge.startRunSnapshot(
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
    return (await _runSnapshotUntilTerminal(
      bridge: _bridge,
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
    return (await _runSnapshotUntilTerminal(
      bridge: _bridge,
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
    var cancelledSnapshot = await _bridge.cancelRunSnapshot(
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
      bridge: _bridge,
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
