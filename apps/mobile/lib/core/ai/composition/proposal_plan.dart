/// Typed view over a `propose_*` tool result.
///
/// The wire shape is stable across domains:
///
/// ```jsonc
/// {
///   "proposal_id": "uuid",
///   "kind":        "trade" | "expense" | "sleep_target_adjust" | ...
///   "status":      "ready" | "needs_clarification",
///   "summary_zh":  "买入 AAPL 100 股 @ $180（盈透）",
///   // status=ready
///   "payload":     { ... per-kind shape ... },
///   "warnings":    [ "currency 未指定，已默认 USD", ... ],
///   "missing":     [ "..." ],
///   // status=needs_clarification
///   "ambiguous_field": "asset",
///   "reason":          "存在多个匹配的资产...",
///   "candidates":      [ { "id": "...", "name": "..." }, ... ]
/// }
/// ```
///
/// [kind] is the raw wire string — shell does **not** validate it
/// against a closed set. Every domain registers its kinds (with
/// label / icon / edit-field metadata) into
/// `proposalKindRegistryProvider`; the propose card looks them up
/// there at render time. Anything that doesn't parse cleanly returns
/// `null`, so the caller falls back to the generic
/// `ToolInvocationCard` — that is the right behaviour for non-propose
/// tool calls and for malformed propose outputs we'd rather not crash
/// on.
library;

sealed class ProposalPlan {
  const ProposalPlan({required this.proposalId, required this.kind});

  final String proposalId;

  /// Raw wire kind. Match against
  /// `proposalKindRegistryProvider`'s entries for presentation.
  final String kind;

  /// Best-effort parser for a tool result `output` payload.
  static ProposalPlan? tryParse(Object? toolOutput) {
    if (toolOutput is! Map) return null;
    final m = toolOutput.map((k, v) => MapEntry(k.toString(), v));
    final id = m['proposal_id'];
    final kind = m['kind'];
    final status = m['status'];
    if (id is! String || kind is! String || status is! String) {
      return null;
    }
    if (kind.isEmpty) return null;

    switch (status) {
      case 'ready':
        final summary = m['summary_zh'];
        final payload = m['payload'];
        if (summary is! String || payload is! Map) return null;
        return ReadyProposalPlan(
          proposalId: id,
          kind: kind,
          summaryZh: summary,
          payload: payload.map((k, v) => MapEntry(k.toString(), v)),
          warnings: _stringList(m['warnings']),
          missing: _stringList(m['missing']),
        );
      case 'needs_clarification':
        final reason = m['reason'];
        return ClarificationProposalPlan(
          proposalId: id,
          kind: kind,
          ambiguousField: (m['ambiguous_field'] as String?) ?? '',
          reason: reason is String ? reason : '需要进一步确认',
          candidates: _candidateList(m['candidates']),
        );
      default:
        return null;
    }
  }
}

/// `status = ready` — the model has fully specified the plan and the user
/// can confirm it as-is.
final class ReadyProposalPlan extends ProposalPlan {
  const ReadyProposalPlan({
    required super.proposalId,
    required super.kind,
    required this.summaryZh,
    required this.payload,
    this.warnings = const <String>[],
    this.missing = const <String>[],
  });

  final String summaryZh;
  final Map<String, Object?> payload;
  final List<String> warnings;
  final List<String> missing;

  String? get(String key) {
    final v = payload[key];
    if (v == null) return null;
    final s = v is String ? v : v.toString();
    return s.isEmpty ? null : s;
  }

  num? num_(String key) {
    final v = payload[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }
}

/// `status = needs_clarification` — backend wants the model to ask the user
/// to disambiguate. The card surfaces the reason + candidates so the user
/// can read it; the model's follow-up prose handles the actual question.
final class ClarificationProposalPlan extends ProposalPlan {
  const ClarificationProposalPlan({
    required super.proposalId,
    required super.kind,
    required this.ambiguousField,
    required this.reason,
    this.candidates = const <ProposalCandidate>[],
  });

  final String ambiguousField;
  final String reason;
  final List<ProposalCandidate> candidates;
}

/// A single disambiguation candidate. Fields beyond `id` / `label` are
/// surfaced as a small subtitle so the user can tell `Citi 储蓄` from
/// `Citi 信用卡` at a glance.
class ProposalCandidate {
  const ProposalCandidate({required this.id, this.label, this.subtitle});

  final String id;
  final String? label;
  final String? subtitle;
}

/// Whether a propose tool name should render as a propose card. `output`
/// being non-null is required because the card needs the parsed plan; while
/// the tool is still in-flight (no output yet) we leave the generic
/// invocation card in place to keep the streaming feedback consistent.
bool isProposeTool(String toolName) => toolName.startsWith('propose_');

List<String> _stringList(Object? v) {
  if (v is! List) return const <String>[];
  return v.whereType<String>().toList(growable: false);
}

List<ProposalCandidate> _candidateList(Object? v) {
  if (v is! List) return const <ProposalCandidate>[];
  return v
      .whereType<Map<Object?, Object?>>()
      .map((m) {
        final mm = m.map((k, vv) => MapEntry(k.toString(), vv));
        final id = mm['id'];
        if (id is! String) return null;
        final label = mm['name'] ?? mm['label'] ?? mm['symbol'];
        final type = mm['type'];
        return ProposalCandidate(
          id: id,
          label: label is String ? label : null,
          subtitle: type is String ? type : null,
        );
      })
      .whereType<ProposalCandidate>()
      .toList(growable: false);
}
