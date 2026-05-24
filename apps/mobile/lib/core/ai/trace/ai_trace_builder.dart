/// Mutable accumulator for an in-flight [AiTrace].
///
/// Lifecycle:
///
///  1. Caller constructs a seed [AiTrace] (post-W-D7: no router).
///  2. The execution layer wraps it in an [AiTraceBuilder].
///  3. Each finished LLM round / tool dispatch calls
///     [AiTraceBuilder.addSpan] (Opik-style hierarchical model).
///  4. On completion the builder produces the immutable [AiTrace] via
///     [AiTraceBuilder.finalize] which is then appended to
///     `AiTraceStore`.
///
/// **Capture level**: `capturePayloads` (verbose) decides whether span
/// `input` / `output` survive into the persisted blob. Default off →
/// metadata-only (small blob, no payload egress into local storage).
/// The user toggles it on the AI transparency page when debugging.
library;

import '../contracts/contracts.dart';

class AiTraceBuilder {
  AiTraceBuilder.fromSeed(AiTrace seed, {bool capturePayloads = false})
    : _seed = seed,
      _capturePayloads = capturePayloads,
      _start = DateTime.parse(seed.startedAtIso);

  final AiTrace _seed;
  final bool _capturePayloads;
  final DateTime _start;
  final List<AiSpan> _spans = <AiSpan>[];
  Map<String, Object?>? _invocation;

  /// Attach an `AiIntentInvocation.toTraceJson()` summary to this
  /// turn (Wave 33). Called once at chat dispatch when the surface
  /// originated from a registered invocation.
  void attachInvocation(Map<String, Object?> invocation) {
    _invocation = invocation;
  }

  /// Record one finished execution span. Wall-clock [startedAt] /
  /// [endedAt] are anchored to the trace start so the persisted span
  /// only carries a relative offset (waterfall-friendly, skew-proof).
  /// Payloads are stripped here when verbose capture is off so they
  /// never reach the JSON blob.
  void addSpan({
    required String id,
    String? parentId,
    required AiSpanKind kind,
    required String name,
    required DateTime startedAt,
    required DateTime endedAt,
    AiSpanStatus status = AiSpanStatus.ok,
    String? errorCode,
    String? errorMessage,
    SpanTokens? tokens,
    String? model,
    String? stopReason,
    Object? input,
    Object? output,
    Map<String, Object?>? attributes,
  }) {
    final off = startedAt.toUtc().difference(_start).inMilliseconds;
    final dur = endedAt.difference(startedAt).inMilliseconds;
    final span = AiSpan(
      id: id,
      parentId: parentId,
      kind: kind,
      name: name,
      startOffsetMs: off < 0 ? 0 : off,
      durationMs: dur < 0 ? 0 : dur,
      status: status,
      errorCode: errorCode,
      errorMessage: errorMessage,
      tokens: tokens,
      model: model,
      stopReason: stopReason,
      input: input,
      output: output,
      attributes: attributes,
    );
    _spans.add(_capturePayloads ? span : span.redacted());
  }

  AiTrace finalize({
    required DateTime finishedAt,
    TerminalReason terminalReason = TerminalReason.done,
  }) {
    final durationMs = finishedAt.toUtc().difference(_start).inMilliseconds;
    final total = durationMs < 0 ? 0 : durationMs;
    return AiTrace(
      requestId: _seed.requestId,
      startedAtIso: _seed.startedAtIso,
      intent: _seed.intent,
      backend: _seed.backend,
      budgetTier: _seed.budgetTier,
      routingReason: _seed.routingReason,
      usedCloud: _seed.usedCloud,
      totalDurationMs: total,
      terminalReason: terminalReason,
      invocation: _invocation,
      spans: _spans.isEmpty
          ? const <AiSpan>[]
          : List<AiSpan>.unmodifiable(<AiSpan>[
              _rootTurnSpan(terminalReason, total),
              ..._spans,
            ]),
    );
  }

  /// Synthesised root that every LLM-round span hangs off of. Only
  /// emitted when there are child spans, so the legacy flat-timeline
  /// fallback still triggers for span-free traces.
  AiSpan _rootTurnSpan(TerminalReason reason, int totalMs) => AiSpan(
    id: kTurnSpanId,
    kind: AiSpanKind.turn,
    name: 'turn',
    startOffsetMs: 0,
    durationMs: totalMs,
    status: switch (reason) {
      TerminalReason.done => AiSpanStatus.ok,
      TerminalReason.userCancel => AiSpanStatus.cancelled,
      _ => AiSpanStatus.error,
    },
    attributes: <String, Object?>{'terminal_reason': reason.wire},
  );
}
