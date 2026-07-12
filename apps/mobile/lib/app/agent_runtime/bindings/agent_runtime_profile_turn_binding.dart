/// App-level profile-turn binding wrapper.
///
/// Core owns the runtime-neutral contract; app composition injects local
/// diagnostics for best-effort trace recording failures.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_profile_turn.dart'
    as core;
import 'package:naviwealth/core/logging/providers.dart';

export 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_profile_turn.dart'
    show
        AgentRuntimeProfileTurnBinding,
        AgentRuntimeProfileTurnBindingKey,
        AgentRuntimeProfileTurnResult,
        AgentRuntimeProfileTurnRunner,
        AgentRuntimeProfileTurnTraceRecorderFactory,
        kSettingsLlmRuntimeCheckAgentId;

final agentRuntimeProfileTurnRunnerProvider =
    Provider<core.AgentRuntimeProfileTurnRunner?>((ref) => null);

final agentRuntimeProfileTurnTraceRecorderFactoryProvider =
    Provider<core.AgentRuntimeProfileTurnTraceRecorderFactory?>((ref) => null);

final agentRuntimeProfileTurnBindingProvider =
    Provider.family<
      core.AgentRuntimeProfileTurnBinding?,
      core.AgentRuntimeProfileTurnBindingKey
    >((ref, key) {
      return agentRuntimeProfileTurnBinding(
        ref,
        agentId: key.agentId,
        domain: key.domain,
        surface: key.surface,
      );
    });

core.AgentRuntimeProfileTurnBinding? agentRuntimeProfileTurnBinding(
  Ref ref, {
  required String agentId,
  required String domain,
  required String surface,
  bool resolveAvailability = true,
}) {
  final recorderFactory = ref.read(
    agentRuntimeProfileTurnTraceRecorderFactoryProvider,
  );
  final recorder = recorderFactory?.call(
    agentId: agentId,
    domain: domain,
    surface: surface,
  );
  void onRecordTraceError(Object error, StackTrace stackTrace) {
    ref
        .read(loggerProvider)
        .w(
          'Agent runtime profile trace recording failed',
          error: error,
          stackTrace: stackTrace,
        );
  }

  if (!resolveAvailability) {
    return core.AgentRuntimeProfileTurnBinding.lazyRunner(
      agentId: agentId,
      domain: domain,
      surface: surface,
      runnerReader: () => ref.read(agentRuntimeProfileTurnRunnerProvider),
      recordTrace: recorder,
      onRecordTraceError: onRecordTraceError,
    );
  }
  final runner = ref.watch(agentRuntimeProfileTurnRunnerProvider);
  if (runner == null) return null;
  return core.AgentRuntimeProfileTurnBinding(
    agentId: agentId,
    domain: domain,
    surface: surface,
    runner: runner,
    recordTrace: recorder,
    onRecordTraceError: onRecordTraceError,
  );
}
