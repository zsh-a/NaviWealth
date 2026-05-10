/// Output of the routing policy.
library;

import '../contracts/contracts.dart';

class RoutingReason {
  const RoutingReason({required this.code, this.messageZh});

  /// Stable short label. Goes into [AiTrace.routingReason] and is also
  /// used as a discriminator in tests.
  final String code;

  /// Optional user-facing message. Used when the decision is
  /// [supported] = false, or when the surface wants to show why the
  /// router picked a constrained path.
  final String? messageZh;
}

class RoutingDecision {
  const RoutingDecision({
    required this.intent,
    required this.backend,
    required this.budgetTier,
    required this.confirmation,
    required this.reason,
    required this.supported,
  });

  final IntentHint intent;
  final Backend backend;
  final BudgetTier budgetTier;
  final Confirmation confirmation;
  final RoutingReason reason;

  /// `false` when the router cannot service this intent under the
  /// current inputs (e.g. plan requested while offline). The caller
  /// should surface [reason.messageZh] rather than execute.
  final bool supported;
}
