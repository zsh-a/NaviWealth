/// Thin entry point around [decideRouting] + [AiTrace] seeding.
///
/// The router is split this way deliberately: [decideRouting] is a
/// pure function (testable, no Riverpod / no `now()`); [AiRouter]
/// adds the side-effecting concerns (clock for trace timestamps,
/// future Phase 2 execution wiring) so callers don't need to reach
/// into the policy module directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/contracts.dart';
import 'routing_decision.dart';
import 'routing_inputs.dart';
import 'routing_policy.dart';

class AiRouter {
  const AiRouter({required this.now});

  /// Injected for testability — tests pass a frozen clock.
  final DateTime Function() now;

  /// Pure routing decision. Phase 1 stops here; Phase 2 will add an
  /// `execute` method that runs the chosen skill or proxies the cloud
  /// call.
  RoutingDecision decide(RoutingInputs inputs) => decideRouting(inputs);

  /// Build the initial trace row for this decision. The caller fills
  /// in [AiTrace.totalDurationMs] / disclosures / spans once
  /// execution completes; until then this is a 'started' record only.
  AiTrace seedTrace({
    required String requestId,
    required RoutingDecision decision,
  }) => AiTrace(
    requestId: requestId,
    startedAtIso: now().toUtc().toIso8601String(),
    intent: decision.intent,
    backend: decision.backend,
    budgetTier: decision.budgetTier,
    routingReason: decision.reason.code,
    usedCloud: decision.backend != Backend.device,
    usedRawLedger: false,
    totalDurationMs: 0,
  );
}

final aiRouterProvider = Provider<AiRouter>(
  (ref) => const AiRouter(now: DateTime.now),
);
