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
    hide agentRuntimeProfileTurnBinding;

core.AgentRuntimeProfileTurnBinding? agentRuntimeProfileTurnBinding(
  Ref ref, {
  required String agentId,
  required String domain,
  required String surface,
  bool resolveAvailability = true,
}) {
  return core.agentRuntimeProfileTurnBinding(
    ref,
    agentId: agentId,
    domain: domain,
    surface: surface,
    resolveAvailability: resolveAvailability,
    onRecordTraceError: (error, stackTrace) {
      ref
          .read(loggerProvider)
          .w(
            'Agent runtime profile trace recording failed',
            error: error,
            stackTrace: stackTrace,
          );
    },
  );
}
