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
  final Set<String> _staleReadModelNames = <String>{};
  Map<String, Object?>? _invocation;

  /// Attach an `AiIntentInvocation.toTraceJson()` summary to this
  /// turn (Wave 33). Called once at chat dispatch when the surface
  /// originated from a registered invocation.
  void attachInvocation(Map<String, Object?> invocation) {
    _invocation = invocation;
  }

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

  /// Record a read model whose `source_hlc_watermark` was behind the
  /// device's local HLC at tool_result time. Phase 2's prep closure
  /// pulls these names out of the finalised trace and injects them
  /// into the *next* request's `FreshnessHint.forceRefreshReadModels`
  /// so the cloud re-projects before dispatching.
  void markStaleReadModel(String readModel) {
    if (readModel.isNotEmpty) _staleReadModelNames.add(readModel);
  }

  /// Whether any disclosure has been recorded with a non-denied
  /// consent. Drives the `usedRawLedger` flag on the finalised trace
  /// (and the inverse user-facing badge).
  bool get _anyConsentedDisclosure =>
      _disclosures.any((d) => d.consent != UserConsent.denied);

  AiTrace finalize({
    required DateTime finishedAt,
    TerminalReason terminalReason = TerminalReason.done,
  }) {
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
      staleReadModelNames: Set<String>.unmodifiable(_staleReadModelNames),
      terminalReason: terminalReason,
      invocation: _invocation,
    );
  }
}
