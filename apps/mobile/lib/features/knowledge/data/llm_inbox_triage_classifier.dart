/// FRB-backed inbox-triage classifier (`docs/domains/knowledgeos-domain.md`
/// §7 + §14.2 "InboxTriageAgent LLM round-trip 替换 heuristic").
///
/// On *any* failure — no profile-backed FRB bridge, provider error, 8s
/// timeout, malformed JSON, schema mismatch, or per-proposal confidence below
/// 0.6 — it degrades silently to [HeuristicInboxTriageClassifier]. It never
/// throws and never blocks the agent tick.
///
/// JSON-in-text (not forced tool_use) keeps this lightweight classifier to one
/// profile completion; plain JSON is reliable enough here.
library;

import 'dart:async';
import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';
import 'inbox_triage_classifier.dart';
import 'inbox_triage_repository.dart';
import 'knowledge_llm_client.dart';

/// Grep the Talker history for `[inbox-triage-llm]` to trace one
/// triage() call end-to-end.
const String _kLogTag = '[inbox-triage-llm]';

/// Same gate the capture classifier uses — proposals the model is less than
/// 60% sure about are dropped (the heuristic is preferred over a shaky LLM
/// guess).
const double _kMinConfidence = 0.6;

/// How many candidate decisions to show the model. The owner's decision
/// set is usually tiny; cap defensively so the prompt stays small.
const int _kMaxDecisionsInPrompt = 12;

const String _kInboxTriageSystemPrompt =
    '你是 NaviWealth KnowledgeOS 的 Inbox 整理助手。给定一条用户的 Inbox '
    'Note(标题 + 正文),以及一份候选 Decision 列表,判断是否值得给出最多三类建议:\n'
    '\n'
    '1. classification — 只判断这条 Note 是否应升级为 Decision:\n'
    '   - 普通材料、想法或定义继续保留为 Note,不要给 classification 建议\n'
    '   - 只有明确权衡选项(含 "应该 / vs / 对比 / 选项")时建议 decision\n'
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
    '  "classification": {"kind": "decision", '
    '"confidence": 数字, "reason_zh": "一句中文", '
    '"decision_options": ["选项 A", "选项 B"], '
    '"expected_outcome": "可选预期结果"} 或 null,\n'
    '  "tags": {"tags": ["..."], "confidence": 数字, "reason_zh": "一句中文"} 或 null,\n'
    '  "link_to_decision": {"decision_ids": ["..."], "confidence": 数字, '
    '"reason_zh": "一句中文"} 或 null\n'
    '}';

String _buildInboxTriageUserMessage(
  KnowledgeNote note,
  List<KnowledgeDecision> decisions,
) {
  final buf = StringBuffer()
    ..writeln('## Note')
    ..writeln('id: ${note.id}')
    ..writeln('title: ${note.title}')
    ..writeln('tags: ${note.tags.isEmpty ? "(无)" : note.tags.join(", ")}')
    ..writeln('body:')
    ..writeln(knowledgeMarkdownWithoutAttachments(note.bodyMd))
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

/// Pull the first balanced `{...}` substring out of the reply, the same way
/// the capture classifier does (handles prose / code-fence wrapping despite
/// the prompt).
Map<String, Object?>? _extractJsonObject(String text) {
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

double? _coerceDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class FrbInboxTriageClassifier implements InboxTriageClassifier {
  const FrbInboxTriageClassifier({
    required this.llmClient,
    this.fallback = const HeuristicInboxTriageClassifier(),
    this.maxTokens = 8192,
    this.requestTimeout = const Duration(seconds: 8),
    this.logger,
  });

  final KnowledgeLlmProfileClient llmClient;
  final InboxTriageClassifier fallback;
  final int maxTokens;
  final Duration requestTimeout;
  final AppLogger? logger;

  @override
  Future<List<InboxProposal>> triage(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
  ) async {
    final corpus =
        '${note.title}\n${knowledgeMarkdownWithoutAttachments(note.bodyMd)}'
            .trim();
    if (corpus.isEmpty) {
      return fallback.triage(note, decisions);
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await llmClient
          .completeProfile(
            messages: <Map<String, Object?>>[
              const <String, Object?>{
                'role': 'system',
                'content': _kInboxTriageSystemPrompt,
              },
              <String, Object?>{
                'role': 'user',
                'content': _buildInboxTriageUserMessage(note, decisions),
              },
            ],
            maxOutputTokens: maxTokens,
            metadata: const <String, Object?>{
              'surface': 'knowledge_inbox_triage',
              'agent_id': 'knowledge_inbox_triage',
            },
          )
          .timeout(requestTimeout);
      logger?.d(
        '$_kLogTag frb response ${stopwatch.elapsedMilliseconds}ms '
        'provider=${response['provider'] ?? "(unknown)"}',
      );

      final body = response['content'];
      if (body is! String || body.trim().isEmpty) {
        logger?.w('$_kLogTag FRB response missing content, falling back');
        return await fallback.triage(note, decisions);
      }
      final json = _extractJsonObject(body);
      if (json == null) {
        logger?.w('$_kLogTag FRB JSON extract failed, falling back');
        return await fallback.triage(note, decisions);
      }
      final proposals = _parseInboxTriageProposals(note, decisions, json);
      logger?.i(
        '$_kLogTag frb parsed ${proposals.length} proposal(s) '
        'for note ${note.id}',
      );
      return proposals;
    } on Object catch (err, st) {
      logger?.w(
        '$_kLogTag frb exception after ${stopwatch.elapsedMilliseconds}ms '
        '(${err.runtimeType}: $err), falling back to heuristic',
        error: err,
        stackTrace: st,
      );
      return await fallback.triage(note, decisions);
    }
  }
}

List<InboxProposal> _parseInboxTriageProposals(
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
  if (kind != 'decision') return null;
  final confidence = _coerceDouble(m['confidence']) ?? 0.0;
  if (confidence < _kMinConfidence) return null;
  final reason = (m['reason_zh'] as String?)?.trim();
  if (reason == null || reason.isEmpty) return null;
  final decisionOptions = _stringList(m['decision_options']);
  if (kind == 'decision' && decisionOptions.length < 2) return null;
  final expectedOutcome = (m['expected_outcome'] as String?)?.trim();

  return InboxProposal(
    kind: InboxProposalKind.classification,
    summaryZh: '看起来像在权衡某个选项 — 建议升级为 Decision draft',
    payload: <String, Object?>{
      'note_id': note.id,
      'kind': kind,
      'confidence': confidence.clamp(0.0, 1.0),
      'reason': reason,
      if (kind == 'decision') 'decision_options': decisionOptions,
      if (expectedOutcome != null && expectedOutcome.isNotEmpty)
        'expected_outcome': expectedOutcome,
    },
    status: InboxProposalStatus.pending,
  );
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .take(8)
      .toList(growable: false);
}

InboxProposal? _parseTags(KnowledgeNote note, Object? raw) {
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
