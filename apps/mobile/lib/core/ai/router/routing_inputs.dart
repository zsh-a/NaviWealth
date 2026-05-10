/// Inputs to the routing decision.
library;

import '../contracts/contracts.dart';

/// User privacy preference. Set in settings; defaults to [standard].
enum PrivacySensitivity {
  /// Default. Cloud reasoning allowed for analysis / planning; raw
  /// ledger only via on-demand [DisclosureRequest] consent flow.
  standard,

  /// Cloud disabled wherever an on-device path exists, even at the
  /// cost of capability. No DisclosureRequest is auto-allowed.
  strict,

  /// Cloud allowed more freely; disclosure consent windows widen.
  /// (Currently behaves like [standard] — placeholder for future
  /// 'always allow within session' policy.)
  open,
}

/// Latency expectation for the surface that issued the intent. Used to
/// prefer device skills for `interactive` and tolerate cloud roundtrips
/// for `background`.
enum LatencyHint { interactive, background }

class RoutingInputs {
  const RoutingInputs({
    required this.intent,
    required this.online,
    this.deviceLlmReady = false,
    this.sensitivity = PrivacySensitivity.standard,
    this.latency = LatencyHint.interactive,
  });

  final IntentHint intent;

  /// Network reachability hint. The router collapses cloud routes when
  /// `false`; it does not retry — that is the caller's concern.
  final bool online;

  /// Phase 5 device-LLM readiness. Pass `false` in Phase 1; the router
  /// will fall back to template / rules paths.
  final bool deviceLlmReady;

  final PrivacySensitivity sensitivity;
  final LatencyHint latency;
}
