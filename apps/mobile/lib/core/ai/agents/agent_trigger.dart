/// Signal-driven trigger contracts and deterministic dispatch coordination.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../contracts/source_identity.dart';
import 'agent.dart';
import 'agent_run_store.dart';
import 'agent_schedule.dart';

enum AgentTriggerKind {
  schedule,
  event,
  threshold,
  stateTransition,
  freshness,
  manual,
}

enum AgentThresholdDirection { risesAbove, fallsBelow }

@immutable
class AgentTriggerSpec {
  const AgentTriggerSpec._({
    required this.id,
    required this.kind,
    this.debounce = Duration.zero,
    this.sourceFamily,
    this.threshold,
    this.thresholdDirection,
    this.fromState,
    this.toState,
    this.freshTarget,
    this.schedule,
  });

  const AgentTriggerSpec.event({
    required String id,
    required String sourceFamily,
    Duration debounce = Duration.zero,
  }) : this._(
         id: id,
         kind: AgentTriggerKind.event,
         sourceFamily: sourceFamily,
         debounce: debounce,
       );

  const AgentTriggerSpec.threshold({
    required String id,
    required double threshold,
    required AgentThresholdDirection direction,
    Duration debounce = Duration.zero,
  }) : this._(
         id: id,
         kind: AgentTriggerKind.threshold,
         threshold: threshold,
         thresholdDirection: direction,
         debounce: debounce,
       );

  const AgentTriggerSpec.stateTransition({
    required String id,
    required String from,
    required String to,
    Duration debounce = Duration.zero,
  }) : this._(
         id: id,
         kind: AgentTriggerKind.stateTransition,
         fromState: from,
         toState: to,
         debounce: debounce,
       );

  const AgentTriggerSpec.freshness({
    required String id,
    bool targetFresh = true,
    Duration debounce = Duration.zero,
  }) : this._(
         id: id,
         kind: AgentTriggerKind.freshness,
         freshTarget: targetFresh,
         debounce: debounce,
       );

  const AgentTriggerSpec.schedule({
    required String id,
    required AgentSchedule schedule,
  }) : this._(id: id, kind: AgentTriggerKind.schedule, schedule: schedule);

  const AgentTriggerSpec.manual({required String id})
    : this._(id: id, kind: AgentTriggerKind.manual);

  final String id;
  final AgentTriggerKind kind;
  final Duration debounce;
  final String? sourceFamily;
  final double? threshold;
  final AgentThresholdDirection? thresholdDirection;
  final String? fromState;
  final String? toState;
  final bool? freshTarget;
  final AgentSchedule? schedule;

  AgentRunTrigger get runProvenance => switch (kind) {
    AgentTriggerKind.schedule => AgentRunTrigger.schedule,
    AgentTriggerKind.event => AgentRunTrigger.event,
    AgentTriggerKind.threshold => AgentRunTrigger.threshold,
    AgentTriggerKind.stateTransition => AgentRunTrigger.stateTransition,
    AgentTriggerKind.freshness => AgentRunTrigger.freshness,
    AgentTriggerKind.manual => AgentRunTrigger.manual,
  };
}

@immutable
class AgentTriggerSignal {
  const AgentTriggerSignal({
    required this.kind,
    required this.key,
    required this.observedAt,
    required this.fingerprint,
    this.source,
    this.previousValue,
    this.currentValue,
    this.previousState,
    this.currentState,
    this.previouslyFresh,
    this.currentlyFresh,
    this.lastRunAt,
  });

  final AgentTriggerKind kind;
  final String key;
  final DateTime observedAt;
  final String fingerprint;
  final SourceIdentity? source;
  final double? previousValue;
  final double? currentValue;
  final String? previousState;
  final String? currentState;
  final bool? previouslyFresh;
  final bool? currentlyFresh;
  final DateTime? lastRunAt;
}

bool shouldDispatchAgentTrigger(
  AgentTriggerSpec spec,
  AgentTriggerSignal signal,
) {
  if (spec.kind != signal.kind) return false;
  return switch (spec.kind) {
    AgentTriggerKind.event => signal.source?.rowFamily == spec.sourceFamily,
    AgentTriggerKind.threshold => _crossedThreshold(spec, signal),
    AgentTriggerKind.stateTransition =>
      signal.previousState == spec.fromState &&
          signal.currentState == spec.toState,
    AgentTriggerKind.freshness =>
      signal.previouslyFresh != signal.currentlyFresh &&
          signal.currentlyFresh == spec.freshTarget,
    AgentTriggerKind.schedule => spec.schedule!.shouldFire(
      now: signal.observedAt,
      lastRunAt: signal.lastRunAt,
    ),
    AgentTriggerKind.manual => true,
  };
}

bool _crossedThreshold(AgentTriggerSpec spec, AgentTriggerSignal signal) {
  final previous = signal.previousValue;
  final current = signal.currentValue;
  final threshold = spec.threshold;
  if (previous == null || current == null || threshold == null) return false;
  return switch (spec.thresholdDirection!) {
    AgentThresholdDirection.risesAbove =>
      previous < threshold && current >= threshold,
    AgentThresholdDirection.fallsBelow =>
      previous > threshold && current <= threshold,
  };
}

typedef AgentTriggerDispatch = Future<AgentRunResult> Function(
  String agentId,
  AgentRunTrigger trigger,
  AgentTriggerSignal signal,
);

/// Debounces and de-duplicates trigger signals before invoking an Agent.
///
/// This coordinator owns trigger policy only. The persisted [AgentRunTrigger]
/// remains execution provenance and never substitutes for [AgentTriggerSpec].
final class AgentTriggerCoordinator {
  AgentTriggerCoordinator({required AgentTriggerDispatch dispatch})
    : _dispatchRun = dispatch;

  final AgentTriggerDispatch _dispatchRun;
  final Map<String, _PendingTrigger> _pending = <String, _PendingTrigger>{};
  final Map<String, String> _lastFingerprint = <String, String>{};
  bool _disposed = false;

  Future<AgentRunResult?> submit({
    required String agentId,
    required AgentTriggerSpec spec,
    required AgentTriggerSignal signal,
  }) {
    if (_disposed || !shouldDispatchAgentTrigger(spec, signal)) {
      return Future<AgentRunResult?>.value();
    }
    final dispatchKey = '$agentId:${spec.id}:${signal.key}';
    if (_lastFingerprint[dispatchKey] == signal.fingerprint) {
      return Future<AgentRunResult?>.value();
    }
    if (spec.debounce == Duration.zero) {
      return _dispatch(
        dispatchKey: dispatchKey,
        agentId: agentId,
        spec: spec,
        signal: signal,
      );
    }

    final completer = Completer<AgentRunResult?>();
    final previous = _pending.remove(dispatchKey);
    previous?.timer.cancel();
    final completers = <Completer<AgentRunResult?>>[
      ...?previous?.completers,
      completer,
    ];
    final timer = Timer(spec.debounce, () async {
      _pending.remove(dispatchKey);
      try {
        final result = await _dispatch(
          dispatchKey: dispatchKey,
          agentId: agentId,
          spec: spec,
          signal: signal,
        );
        for (final item in completers) {
          if (!item.isCompleted) item.complete(result);
        }
      } on Object catch (error, stackTrace) {
        for (final item in completers) {
          if (!item.isCompleted) item.completeError(error, stackTrace);
        }
      }
    });
    _pending[dispatchKey] = _PendingTrigger(
      timer: timer,
      completers: completers,
    );
    return completer.future;
  }

  Future<AgentRunResult?> _dispatch({
    required String dispatchKey,
    required String agentId,
    required AgentTriggerSpec spec,
    required AgentTriggerSignal signal,
  }) async {
    final result = await _dispatchRun(agentId, spec.runProvenance, signal);
    _lastFingerprint[dispatchKey] = signal.fingerprint;
    return result;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final pending in _pending.values) {
      pending.timer.cancel();
      for (final completer in pending.completers) {
        if (!completer.isCompleted) completer.complete();
      }
    }
    _pending.clear();
  }
}

final class _PendingTrigger {
  const _PendingTrigger({required this.timer, required this.completers});

  final Timer timer;
  final List<Completer<AgentRunResult?>> completers;
}
