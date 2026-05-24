/// Per-request AI execution record.
///
/// Stored locally only — never replicated via OpLog. Drives the user-
/// visible 'AI 透明度' affordance (tool count, spans, badge) and the
/// in-app audit page. 30-day rolling retention; older rows are pruned
/// by [AiTraceStore].
///
/// Post-W-D7 there is no router decision and no cloud disclosure; the
/// trace records what the device runtime did.
library;

import 'ai_span.dart';
import 'intent.dart';
import 'privacy_budget.dart' show BudgetTier, BudgetTierWire;

/// §4.6 W-D6 — [AiTrace.routingReason] value set when the on-device
/// LLM runtime (user's own key, direct to provider) handled the turn.
/// Distinguishes device-LLM-direct from the zero-model rules-device
/// path so the transparency badge can say "未经我方服务器".
const String kDeviceLlmDirectRoutingReason = 'device_llm_direct';

/// Where the turn was executed.
///
/// **Live producers** (post-W-D7):
///  - [Backend.device] — every chat turn, plus Layer 4 device Vision ingest.
///
/// **Fossil values**, kept only to:
///  1. deserialize old AiTrace rows written before W-D7;
///  2. let `features/ingest/data/providers.dart` tag its Vision trace
///     (`layer4_cloud_vision`) — that flow predates W-D7 and is itself
///     pending a separate audit (see ingest module).
///  - [Backend.cloud] — has the ingest producer above; otherwise fossil.
///  - [Backend.hybrid] — no live producer anywhere; only old DB rows.
///
/// Per `docs/ai-boundary-audit.md`, we don't add new "maybe useful"
/// enum values; if a future runtime needs a new value, add it then.
enum Backend { device, cloud, hybrid }

extension BackendWire on Backend {
  String get wire => switch (this) {
    Backend.device => 'device',
    Backend.cloud => 'cloud',
    Backend.hybrid => 'hybrid',
  };

  static Backend parse(String s) => switch (s) {
    'device' => Backend.device,
    'cloud' => Backend.cloud,
    'hybrid' => Backend.hybrid,
    _ => Backend.device,
  };
}

/// How the turn ended (Wave 30). Distinguishes "normal completion" from
/// "the user cancelled mid-stream" from "the stream raised an error" —
/// today these all collapse into a single trace row, which loses
/// signal for the transparency surface and for future SLO dashboards.
enum TerminalReason {
  /// Stream emitted the terminal `done` frame normally.
  done,
  /// Stream errored out mid-flight (network / upstream / parser).
  streamError,
  /// User explicitly cancelled (cancel button / navigated away).
  userCancel,
  /// Policy denied dispatch — synthesised `tool_result {error: policy_denied}`.
  policyDenied,
  /// Stream closed before the `done` frame and no error fired (peer
  /// reset, timeout, etc.). Less informative than `streamError`.
  closedEarly,
}

extension TerminalReasonWire on TerminalReason {
  String get wire => switch (this) {
    TerminalReason.done => 'done',
    TerminalReason.streamError => 'stream_error',
    TerminalReason.userCancel => 'user_cancel',
    TerminalReason.policyDenied => 'policy_denied',
    TerminalReason.closedEarly => 'closed_early',
  };

  static TerminalReason parse(String s) => switch (s) {
    'done' => TerminalReason.done,
    'stream_error' => TerminalReason.streamError,
    'user_cancel' => TerminalReason.userCancel,
    'policy_denied' => TerminalReason.policyDenied,
    'closed_early' => TerminalReason.closedEarly,
    _ => TerminalReason.done,
  };
}

class AiTrace {
  const AiTrace({
    required this.requestId,
    required this.startedAtIso,
    required this.intent,
    required this.backend,
    required this.budgetTier,
    required this.routingReason,
    required this.totalDurationMs,
    this.terminalReason = TerminalReason.done,
    this.invocation,
    this.spans = const <AiSpan>[],
  });

  final String requestId;
  final String startedAtIso;
  final IntentHint intent;
  final Backend backend;
  final BudgetTier budgetTier;

  /// Short label for which runtime handled the turn — `device_llm_direct`
  /// (see [kDeviceLlmDirectRoutingReason]), `device_unavailable`, or
  /// `layer4_cloud_vision` (ingest). Free-form for now.
  final String routingReason;

  final int totalDurationMs;

  /// How the turn ended. Defaults to [TerminalReason.done] for
  /// callers that haven't been updated yet (Wave 30).
  final TerminalReason terminalReason;

  /// Wave 33 — entry-point attribution. Captures the
  /// `AiIntentInvocation` summary (source / intent / object_type /
  /// object_id / context_keys) so the transparency page can answer
  /// "which surface triggered this AI call?". Local-only — not on the
  /// chat-request wire. `null` for turns invoked the old way (typing
  /// in the chat tab directly).
  final Map<String, Object?>? invocation;

  /// Opik-style hierarchical execution spans (LLM rounds + tool
  /// calls + the synthesised root `turn`). Additive: empty for traces
  /// written before spans existed, so the transparency page falls
  /// back to the flat timeline. Flat list + `parentId`; the tree is
  /// rebuilt in the UI.
  final List<AiSpan> spans;

  /// True when this trace carries the new span model (drives the
  /// waterfall view vs. the legacy flat-timeline fallback).
  bool get hasSpans => spans.isNotEmpty;

  Iterable<AiSpan> get llmSpans =>
      spans.where((s) => s.kind == AiSpanKind.llm);

  Iterable<AiSpan> get toolSpans =>
      spans.where((s) => s.kind == AiSpanKind.tool);

  /// Number of inner LLM round-trips (Opik "spans" count proxy).
  int get llmRoundCount => llmSpans.length;

  int get errorSpanCount => spans.where((s) => s.isError).length;

  /// Sum of every LLM span's token usage — powers the list-page
  /// aggregate header and the per-trace token chip.
  SpanTokens get tokenTotals {
    var i = 0, o = 0, cr = 0, cw = 0;
    for (final s in llmSpans) {
      final t = s.tokens;
      if (t == null) continue;
      i += t.input;
      o += t.output;
      cr += t.cacheRead;
      cw += t.cacheWrite;
    }
    return SpanTokens(input: i, output: o, cacheRead: cr, cacheWrite: cw);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'request_id': requestId,
    'started_at': startedAtIso,
    'intent': intent.toJson(),
    'backend': backend.wire,
    'budget_tier': budgetTier.wire,
    'routing_reason': routingReason,
    'total_duration_ms': totalDurationMs,
    'terminal_reason': terminalReason.wire,
    if (invocation != null && invocation!.isNotEmpty)
      'invocation': invocation,
    if (spans.isNotEmpty)
      'spans': spans.map((s) => s.toJson()).toList(growable: false),
  };

  factory AiTrace.fromJson(Map<String, Object?> json) {
    final id = json['request_id'];
    final ts = json['started_at'];
    final it = json['intent'];
    final bk = json['backend'];
    final bt = json['budget_tier'];
    final rr = json['routing_reason'];
    final td = json['total_duration_ms'];
    return AiTrace(
      requestId: id is String ? id : '',
      startedAtIso: ts is String ? ts : '',
      intent: it is Map
          ? IntentHint.fromJson(_strKeyed(it))
          : const IntentHint(
              capability: Capability.analyze,
              risk: RiskLevel.info,
            ),
      backend: bk is String ? BackendWire.parse(bk) : Backend.device,
      budgetTier: bt is String
          ? BudgetTierWire.parse(bt)
          : BudgetTier.standard,
      routingReason: rr is String ? rr : '',
      totalDurationMs: td is int ? td : 0,
      terminalReason: switch (json['terminal_reason']) {
        final String s => TerminalReasonWire.parse(s),
        _ => TerminalReason.done,
      },
      invocation: switch (json['invocation']) {
        final Map<Object?, Object?> raw => _strKeyed(raw),
        _ => null,
      },
      spans: _list(json['spans'], AiSpan.fromJson),
    );
  }
}

Map<String, Object?> _strKeyed(Map<Object?, Object?> raw) =>
    raw.map((k, v) => MapEntry(k.toString(), v));

List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) f) {
  if (raw is! List) return <T>[];
  final out = <T>[];
  for (final item in raw) {
    if (item is Map) {
      out.add(f(_strKeyed(item)));
    }
  }
  return out;
}
