/// Mutable accumulator for an in-flight [AiTrace].
///
/// Lifecycle:
///
///  1. Router emits a *seed* trace via `AiRouter.seedTrace`.
///  2. The execution layer wraps it in an [AiTraceBuilder].
///  3. Each tool invocation / disclosure exchange calls
///     [AiTraceBuilder.addToolCall] / [AiTraceBuilder.addDisclosure].
///  4. On completion the builder produces the immutable [AiTrace] via
///     [AiTraceBuilder.finalize] which is then appended to
///     `AiTraceStore`.
library;

import '../contracts/contracts.dart';

class AiTraceBuilder {
  AiTraceBuilder.fromSeed(AiTrace seed) : _seed = seed;

  final AiTrace _seed;
  final List<TraceToolCall> _tools = <TraceToolCall>[];
  final List<DisclosureSummary> _disclosures = <DisclosureSummary>[];

  void addToolCall({
    required String name,
    required Duration duration,
    bool ok = true,
  }) {
    _tools.add(
      TraceToolCall(name: name, durationMs: duration.inMilliseconds, ok: ok),
    );
  }

  void addDisclosure(DisclosureSummary summary) {
    _disclosures.add(summary);
  }

  /// Whether any disclosure has been recorded with a non-denied
  /// consent. Drives the `usedRawLedger` flag on the finalised trace
  /// (and the inverse user-facing badge).
  bool get _anyConsentedDisclosure =>
      _disclosures.any((d) => d.consent != UserConsent.denied);

  AiTrace finalize({required DateTime finishedAt}) {
    final start = DateTime.parse(_seed.startedAtIso);
    final durationMs = finishedAt.toUtc().difference(start).inMilliseconds;
    return AiTrace(
      requestId: _seed.requestId,
      startedAtIso: _seed.startedAtIso,
      intent: _seed.intent,
      backend: _seed.backend,
      budgetTier: _seed.budgetTier,
      routingReason: _seed.routingReason,
      usedCloud: _seed.usedCloud,
      usedRawLedger: _anyConsentedDisclosure,
      totalDurationMs: durationMs < 0 ? 0 : durationMs,
      disclosures: List<DisclosureSummary>.unmodifiable(_disclosures),
      toolCalls: List<TraceToolCall>.unmodifiable(_tools),
    );
  }
}
