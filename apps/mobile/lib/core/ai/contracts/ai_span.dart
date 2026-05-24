/// Hierarchical execution span for one slice of an AI turn (Opik-style
/// observability).
///
/// **Why a span model on [AiTrace]?** The agent loop is inherently
/// multi-round (LLM round → tool calls → LLM round → …). The previous
/// flat tool-call list lost the *round structure*, the per-LLM-call
/// token/model/stop facts, and the start offsets needed to draw a
/// waterfall. `AiSpan` is now the single execution record — it
/// serialises into the same `payload_json` blob and never enters the
/// OpLog. Traces written before the span model simply have no
/// `spans` (no backward-compat shim; they age out within the 30-day
/// retention window).
///
/// Storage shape is a **flat list with `parentId`** — the tree is
/// rebuilt in the UI (`buildSpanTree`). This keeps the JSON blob
/// append-friendly and avoids recursive (de)serialisation.
///
/// `startOffsetMs` is measured **relative to `AiTrace.startedAtIso`**,
/// not an absolute timestamp: waterfall maths becomes trivial, the
/// blob stays compact, and device clock skew can't distort the chart.
///
/// Contracts-layer type — deliberately self-contained ([SpanTokens]
/// instead of the features-layer `TokenUsage`) so the contract surface
/// has no upward dependency.
library;

/// Stable id of the synthesised root [AiSpanKind.turn] span. The agent
/// loop parents its LLM-round spans onto this id; [AiTraceBuilder]
/// injects the matching root at finalize.
const String kTurnSpanId = 'turn';

/// Per-round provider token accounting. Mirrors the four counters the
/// features-layer `TokenUsage` carries; kept local so this contract
/// doesn't depend on `lib/features/`.
class SpanTokens {
  const SpanTokens({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
  });

  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;

  int get total => input + output + cacheRead + cacheWrite;

  Map<String, Object?> toJson() => <String, Object?>{
    'input': input,
    'output': output,
    'cache_read': cacheRead,
    'cache_write': cacheWrite,
  };

  factory SpanTokens.fromJson(Map<String, Object?> json) => SpanTokens(
    input: _int(json['input']),
    output: _int(json['output']),
    cacheRead: _int(json['cache_read']),
    cacheWrite: _int(json['cache_write']),
  );

  static int _int(Object? v) => v is int
      ? v
      : v is num
      ? v.toInt()
      : 0;
}

enum AiSpanKind {
  /// Root span — the whole user turn. Exactly one per trace; the
  /// builder synthesises it at finalize so it exists even for a
  /// 0-round / errored turn.
  turn,

  /// One inner Anthropic round-trip (request → streamed response).
  llm,

  /// One device tool dispatch (`get_*` / `propose_*` / `read_*` …).
  tool,
}

extension AiSpanKindWire on AiSpanKind {
  String get wire => switch (this) {
    AiSpanKind.turn => 'turn',
    AiSpanKind.llm => 'llm',
    AiSpanKind.tool => 'tool',
  };

  static AiSpanKind parse(String s) => switch (s) {
    'turn' => AiSpanKind.turn,
    'llm' => AiSpanKind.llm,
    'tool' => AiSpanKind.tool,
    _ => AiSpanKind.tool,
  };
}

enum AiSpanStatus { ok, error, cancelled }

extension AiSpanStatusWire on AiSpanStatus {
  String get wire => switch (this) {
    AiSpanStatus.ok => 'ok',
    AiSpanStatus.error => 'error',
    AiSpanStatus.cancelled => 'cancelled',
  };

  static AiSpanStatus parse(String s) => switch (s) {
    'ok' => AiSpanStatus.ok,
    'error' => AiSpanStatus.error,
    'cancelled' => AiSpanStatus.cancelled,
    _ => AiSpanStatus.ok,
  };
}

class AiSpan {
  const AiSpan({
    required this.id,
    this.parentId,
    required this.kind,
    required this.name,
    required this.startOffsetMs,
    required this.durationMs,
    this.status = AiSpanStatus.ok,
    this.errorCode,
    this.errorMessage,
    this.tokens,
    this.model,
    this.stopReason,
    this.input,
    this.output,
    this.attributes,
  });

  final String id;

  /// `null` ⇒ root (the [AiSpanKind.turn] span). Every other span
  /// points at the span that *caused* it (an LLM round span for a
  /// tool call; the turn span for an LLM round).
  final String? parentId;

  final AiSpanKind kind;

  /// Human label: `turn` / `llm:round-1` / `tool:get_holdings`.
  final String name;

  /// Milliseconds after `AiTrace.startedAtIso` that this span began.
  final int startOffsetMs;
  final int durationMs;

  final AiSpanStatus status;
  final String? errorCode;
  final String? errorMessage;

  /// LLM spans only — provider token accounting for that round.
  final SpanTokens? tokens;

  /// LLM spans only.
  final String? model;

  /// LLM spans only — Anthropic verbatim stop reason for the round.
  final String? stopReason;

  /// Tool span: parsed tool input args. LLM span: a short request
  /// digest. `null` unless verbose capture is on (privacy + blob
  /// size — see [AiTraceBuilder]).
  final Object? input;

  /// Tool span: tool result JSON. LLM span: assistant text digest.
  /// `null` unless verbose capture is on.
  final Object? output;

  /// Free-form per-kind extras (round index, tool_use id, freshness
  /// watermark, …). Always cheap/scalar — never raw ledger rows.
  final Map<String, Object?>? attributes;

  int get endOffsetMs => startOffsetMs + durationMs;

  bool get isError => status == AiSpanStatus.error;

  /// Drop the (potentially large / sensitive) payloads, keep all
  /// structural + metric fields. Used when verbose capture is off so
  /// the persisted blob stays small.
  AiSpan redacted() => AiSpan(
    id: id,
    parentId: parentId,
    kind: kind,
    name: name,
    startOffsetMs: startOffsetMs,
    durationMs: durationMs,
    status: status,
    errorCode: errorCode,
    errorMessage: errorMessage,
    tokens: tokens,
    model: model,
    stopReason: stopReason,
    attributes: attributes,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (parentId != null) 'parent_id': parentId,
    'kind': kind.wire,
    'name': name,
    'start_ms': startOffsetMs,
    'dur_ms': durationMs,
    'status': status.wire,
    if (errorCode != null) 'err_code': errorCode,
    if (errorMessage != null) 'err_msg': errorMessage,
    if (tokens != null) 'usage': tokens!.toJson(),
    if (model != null) 'model': model,
    if (stopReason != null) 'stop': stopReason,
    if (input != null) 'input': input,
    if (output != null) 'output': output,
    if (attributes != null && attributes!.isNotEmpty) 'attrs': attributes,
  };

  factory AiSpan.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final parent = json['parent_id'];
    final kind = json['kind'];
    final name = json['name'];
    final start = json['start_ms'];
    final dur = json['dur_ms'];
    final status = json['status'];
    final usage = json['usage'];
    final attrs = json['attrs'];
    return AiSpan(
      id: id is String ? id : '',
      parentId: parent is String && parent.isNotEmpty ? parent : null,
      kind: kind is String ? AiSpanKindWire.parse(kind) : AiSpanKind.tool,
      name: name is String ? name : '',
      startOffsetMs: start is int ? start : 0,
      durationMs: dur is int ? dur : 0,
      status: status is String
          ? AiSpanStatusWire.parse(status)
          : AiSpanStatus.ok,
      errorCode: json['err_code'] is String ? json['err_code'] as String : null,
      errorMessage: json['err_msg'] is String
          ? json['err_msg'] as String
          : null,
      tokens: usage is Map
          ? SpanTokens.fromJson(usage.map((k, v) => MapEntry('$k', v)))
          : null,
      model: json['model'] is String ? json['model'] as String : null,
      stopReason: json['stop'] is String ? json['stop'] as String : null,
      input: json['input'],
      output: json['output'],
      attributes: attrs is Map ? attrs.map((k, v) => MapEntry('$k', v)) : null,
    );
  }
}
