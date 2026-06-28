/// LLM-backed inbox-triage classifier (`docs/domains/knowledgeos-domain.md`
/// §7 + §14.2 "InboxTriageAgent LLM round-trip 替换 heuristic").
///
/// Same shape as [LlmCaptureClassifier]: wrap the user's configured
/// [DeviceLlmClient], compose one tight system prompt that emits a
/// single structured JSON object covering all three proposal kinds
/// (classification / tags / link_to_decision), parse + validate, and
/// map the result onto the same [InboxProposal] envelopes the heuristic
/// produces. **≤ 1 LLM round-trip per note.**
///
/// On *any* failure — no LLM profile (the provider hands a heuristic
/// instance instead, so this class is only constructed with a client),
/// network / provider error, 8s timeout, malformed JSON, schema
/// mismatch, or per-proposal confidence below 0.6 — it degrades
/// silently to [HeuristicInboxTriageClassifier]. It never throws and
/// never blocks the agent tick.
///
/// JSON-in-text (not forced tool_use) for the same reason as
/// [LlmCaptureClassifier]: the shared wire exposes `tools` but not
/// `tool_choice`, and plain JSON is reliable enough here.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/ai/runtime/device/anthropic/anthropic_client.dart';
import '../../../core/ai/runtime/device/anthropic/anthropic_wire.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/knowledge_models.dart';
import 'inbox_triage_classifier.dart';
import 'inbox_triage_repository.dart';

/// Grep the Talker history for `[inbox-triage-llm]` to trace one
/// triage() call end-to-end.
const String _kLogTag = '[inbox-triage-llm]';

/// Same gate [LlmCaptureClassifier] uses — proposals the model is less
/// than 60% sure about are dropped (the heuristic is preferred over a
/// shaky LLM guess).
const double _kMinConfidence = 0.6;

/// How many candidate decisions to show the model. The owner's decision
/// set is usually tiny; cap defensively so the prompt stays small.
const int _kMaxDecisionsInPrompt = 12;

class LlmInboxTriageClassifier implements InboxTriageClassifier {
  const LlmInboxTriageClassifier({
    required this.client,
    this.fallback = const HeuristicInboxTriageClassifier(),
    // Generous budget so extended-thinking models can finish (see the
    // matching note in LlmCaptureClassifier).
    this.maxTokens = 8192,
    // §14.2 spec: 8s per-note budget. The heuristic fallback covers the
    // timeout case so a slow note never stalls the tick.
    this.requestTimeout = const Duration(seconds: 8),
    this.logger,
  });

  final DeviceLlmClient client;
  final InboxTriageClassifier fallback;
  final int maxTokens;
  final Duration requestTimeout;

  /// Optional structured logger — null means silent (test default).
  final AppLogger? logger;

  static const String _system =
      '你是 NaviWealth KnowledgeOS 的 Inbox 整理助手。给定一条用户的 Inbox '
      'Note(标题 + 正文),以及一份候选 Decision 列表,判断是否值得给出最多三类建议:\n'
      '\n'
      '1. classification — 这条 note 该归为哪一类:\n'
      '   - note: 普通笔记(默认,没有明显结构 → 不要给 classification 建议)\n'
      '   - decision_candidate: 在权衡某个选项的决策(含 "应该 / vs / 对比 / 选项")\n'
      '   - concept_candidate: 短小的概念定义\n'
      '2. tags — 适合这条 note 的 1..4 个小写短 tag(例如 fire / options / health)。'
      '若 note 已有 tag 或想不出合适的就留空。\n'
      '3. link_to_decision — 这条 note 与候选列表里哪些 Decision 相关(用它们的 id)。'
      '不相关就留空。\n'
      '\n'
      '只在确有把握时给建议;宁缺毋滥。每类都带一个 0..1 的 confidence,'
      '低于 0.6 的本系统会自动丢弃。\n'
      '\n'
      '仅输出一个 JSON 对象,**不要任何额外文字 / Markdown / 代码栅栏**。schema:\n'
      '{\n'
      '  "classification": {"kind": "decision_candidate|concept_candidate", '
      '"confidence": 数字, "reason_zh": "一句中文"} 或 null,\n'
      '  "tags": {"tags": ["..."], "confidence": 数字, "reason_zh": "一句中文"} 或 null,\n'
      '  "link_to_decision": {"decision_ids": ["..."], "confidence": 数字, '
      '"reason_zh": "一句中文"} 或 null\n'
      '}';

  @override
  Future<List<InboxProposal>> triage(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
  ) async {
    final corpus = '${note.title}\n${note.bodyMd}'.trim();
    if (corpus.isEmpty) {
      return fallback.triage(note, decisions);
    }

    final stopwatch = Stopwatch()..start();
    try {
      final userMsg = _buildUserMessage(note, decisions);
      final request = AnthropicRequest(
        model: client.config.model,
        maxTokens: maxTokens,
        system: _system,
        messages: <AnthropicChatMessage>[
          AnthropicChatMessage.text('user', userMsg),
        ],
        stream: false,
      );
      final completion = await client
          .complete(request, cancelToken: CancelToken())
          .timeout(requestTimeout);
      logger?.d(
        '$_kLogTag response ${stopwatch.elapsedMilliseconds}ms '
        'blocks=${completion.content.length} '
        'stop=${completion.stopReason ?? "(null)"}',
      );

      final body = _extractText(completion);
      if (body == null) {
        logger?.w('$_kLogTag no text block, falling back to heuristic');
        return fallback.triage(note, decisions);
      }
      final json = _extractJsonObject(body);
      if (json == null) {
        logger?.w('$_kLogTag JSON extract failed, falling back');
        return fallback.triage(note, decisions);
      }

      final proposals = _parseProposals(note, decisions, json);
      // A well-formed but empty answer ("nothing worth proposing") is a
      // valid LLM verdict — do NOT fall back, that would re-introduce
      // heuristic noise the model deliberately suppressed.
      logger?.i(
        '$_kLogTag parsed ${proposals.length} proposal(s) for note ${note.id}',
      );
      return proposals;
    } on Object catch (err, st) {
      logger?.w(
        '$_kLogTag exception after ${stopwatch.elapsedMilliseconds}ms '
        '(${err.runtimeType}: $err), falling back to heuristic',
        error: err,
        stackTrace: st,
      );
      return fallback.triage(note, decisions);
    }
  }

  static String _buildUserMessage(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
  ) {
    final buf = StringBuffer()
      ..writeln('## Note')
      ..writeln('id: ${note.id}')
      ..writeln('title: ${note.title}')
      ..writeln('tags: ${note.tags.isEmpty ? "(无)" : note.tags.join(", ")}')
      ..writeln('body:')
      ..writeln(note.bodyMd)
      ..writeln()
      ..writeln('## 候选 Decisions');
    if (decisions.isEmpty) {
      buf.writeln('(无 — link_to_decision 必须为 null)');
    } else {
      for (final d in decisions.take(_kMaxDecisionsInPrompt)) {
        buf.writeln('- id=${d.id} question="${d.question}"');
      }
    }
    return buf.toString();
  }

  List<InboxProposal> _parseProposals(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
    Map<String, Object?> json,
  ) {
    final out = <InboxProposal>[];

    final classification = _parseClassification(note, json['classification']);
    if (classification != null) out.add(classification);

    final tags = _parseTags(note, json['tags']);
    if (tags != null) out.add(tags);

    final link = _parseLink(note, decisions, json['link_to_decision']);
    if (link != null) out.add(link);

    return out;
  }

  InboxProposal? _parseClassification(KnowledgeNote note, Object? raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final kind = (m['kind'] as String?)?.trim() ?? '';
    if (kind != 'decision_candidate' && kind != 'concept_candidate') {
      return null;
    }
    final confidence = _coerceDouble(m['confidence']) ?? 0.0;
    if (confidence < _kMinConfidence) return null;
    final reason = (m['reason_zh'] as String?)?.trim();
    if (reason == null || reason.isEmpty) return null;

    final label = kind == 'decision_candidate'
        ? '看起来像在权衡某个选项 — 建议升级为 Decision draft'
        : '短小定义型笔记 — 建议提取为 Concept';
    return InboxProposal(
      kind: InboxProposalKind.classification,
      summaryZh: label,
      payload: <String, Object?>{
        'note_id': note.id,
        'kind': kind,
        'confidence': confidence.clamp(0.0, 1.0),
        'reason': reason,
      },
      status: InboxProposalStatus.pending,
    );
  }

  InboxProposal? _parseTags(KnowledgeNote note, Object? raw) {
    // Respect the heuristic's "already user-tagged → skip" rule.
    if (note.tags.isNotEmpty) return null;
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final confidence = _coerceDouble(m['confidence']) ?? 0.0;
    if (confidence < _kMinConfidence) return null;
    final rawTags = m['tags'];
    final tags = rawTags is List
        ? rawTags
              .whereType<String>()
              .map((t) => t.trim().toLowerCase())
              .where((t) => t.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    if (tags.isEmpty) return null;
    final reason = (m['reason_zh'] as String?)?.trim();
    if (reason == null || reason.isEmpty) return null;

    return InboxProposal(
      kind: InboxProposalKind.tags,
      summaryZh: '建议加上 tags: ${tags.join("/")}',
      payload: <String, Object?>{
        'note_id': note.id,
        'tags': tags,
        'reason': reason,
      },
      status: InboxProposalStatus.pending,
    );
  }

  InboxProposal? _parseLink(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
    Object? raw,
  ) {
    if (decisions.isEmpty) return null;
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final confidence = _coerceDouble(m['confidence']) ?? 0.0;
    if (confidence < _kMinConfidence) return null;
    final rawIds = m['decision_ids'];
    final requested = rawIds is List
        ? rawIds
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
        : const <String>{};
    // Only keep ids the model didn't hallucinate — they must exist in
    // the candidate set we handed it.
    final valid = decisions
        .where((d) => requested.contains(d.id))
        .take(3)
        .toList(growable: false);
    if (valid.isEmpty) return null;
    final reason = (m['reason_zh'] as String?)?.trim();
    if (reason == null || reason.isEmpty) return null;

    return InboxProposal(
      kind: InboxProposalKind.linkToDecision,
      summaryZh: valid.length == 1
          ? '看起来和决策 "${valid.first.question}" 相关 — 建议关联'
          : '看起来和 ${valid.length} 条决策相关 — 建议关联',
      payload: <String, Object?>{
        'note_id': note.id,
        'related_decision_ids': valid.map((d) => d.id).toList(growable: false),
        'reason': reason,
      },
      status: InboxProposalStatus.pending,
    );
  }

  static String? _extractText(AnthropicCompletion completion) {
    for (final block in completion.content) {
      if (block is! Map) continue;
      if (block['type'] == 'text' && block['text'] is String) {
        return block['text'] as String;
      }
    }
    return null;
  }

  /// Pull the first balanced `{...}` substring out of the reply, the
  /// same way [LlmCaptureClassifier] does (handles prose / code-fence
  /// wrapping despite the prompt).
  static Map<String, Object?>? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (inString) {
        if (c == r'\') {
          escape = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          final slice = text.substring(start, i + 1);
          try {
            final decoded = jsonDecode(slice);
            if (decoded is Map) {
              return decoded.map((k, v) => MapEntry(k.toString(), v));
            }
            return null;
          } on FormatException {
            return null;
          }
        }
      }
    }
    return null;
  }

  static double? _coerceDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
