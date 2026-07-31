/// Inbox-triage classifier seam (`docs/domains/knowledgeos-domain.md` §7 + §14.2).
///
/// The [InboxTriageAgent] delegates "what should we propose for this
/// note" to an [InboxTriageClassifier]. Two implementations exist,
/// mirroring the capture-classifier layering:
///
/// - [HeuristicInboxTriageClassifier] — the pure-Dart, dependency-free
///   baseline. It owns the original keyword / token-overlap heuristics
///   verbatim (moved here from the agent, behaviour-preserving) and is
///   the safe fallback when no LLM is configured or the LLM round-trip
///   fails.
/// - The LLM-backed implementation lives in
///   `llm_inbox_triage_classifier.dart` so this file stays free of
///   network / provider imports. It degrades to the heuristic on *any*
///   failure, so the no-LLM (Web / no key) path behaves exactly as
///   before.
///
/// `triage` is async so both paths share the same shape; the heuristic
/// returns synchronously inside the future. Returning a list of
/// [InboxProposal]s (instead of writing the side-table directly) keeps
/// the classifier pure — the agent owns persistence + the dismissed-kind
/// merge.
library;

import '../domain/knowledge_models.dart';
import 'inbox_triage_repository.dart';

/// Common interface so the agent can swap heuristic ↔ LLM without
/// touching its run loop, the side-table schema, or the propose tools.
abstract class InboxTriageClassifier {
  /// Produce up to three proposals (classification / tags /
  /// link_to_decision) for [note]. [decisions] is the owner's decision
  /// set, pulled once by the agent and shared across notes for the
  /// link_to_decision heuristic / prompt.
  Future<List<InboxProposal>> triage(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
  );
}

/// Deterministic pure-Dart classifier — the §7 MVP heuristic surface,
/// preserved verbatim from the original agent. Stateless, so a single
/// `const` instance can be shared everywhere.
class HeuristicInboxTriageClassifier implements InboxTriageClassifier {
  const HeuristicInboxTriageClassifier();

  @override
  Future<List<InboxProposal>> triage(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
  ) async {
    return proposals(note, decisions);
  }

  /// Synchronous entry point — also used by the FRB-backed classifier fallback
  /// so provider failures degrade to the exact same heuristic output.
  static List<InboxProposal> proposals(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
  ) {
    final body = note.bodyMd;
    final lower = '${note.title}\n$body'.toLowerCase();
    final out = <InboxProposal>[];

    final classification = _classify(note);
    if (classification != null) out.add(classification);

    final tagSuggestion = _suggestTags(note);
    if (tagSuggestion != null) out.add(tagSuggestion);

    final link = _suggestLink(note, decisions, lower);
    if (link != null) out.add(link);

    return out;
  }

  static InboxProposal? _classify(KnowledgeNote note) {
    final body = note.bodyMd.trim();
    final title = note.title.trim();
    final hasQuestion =
        body.contains('?') || body.contains('？') || title.contains('?');
    final long = body.length > 240;
    final hasOptionsLanguage = RegExp(
      r'(option|选项|对比|vs\.?|trade-?off|权衡|犹豫|决定|应该)',
      caseSensitive: false,
    ).hasMatch('$title\n$body');
    final options = _decisionOptions('$title\n$body');

    if (long && (hasQuestion || hasOptionsLanguage) && options.length >= 2) {
      return InboxProposal(
        kind: InboxProposalKind.classification,
        summaryZh: '看起来像在权衡某个选项 — 建议升级为 Decision draft',
        payload: <String, Object?>{
          'note_id': note.id,
          'kind': 'decision',
          'confidence': 0.6,
          'reason': '正文较长且包含 "对比 / 选项 / 应该 / ?" 类语言',
          'decision_options': options,
        },
        status: InboxProposalStatus.pending,
      );
    }
    // Single capitalised noun phrase / short body → Concept.
    if (body.length < 120 && title.isNotEmpty && !hasQuestion) {
      return InboxProposal(
        kind: InboxProposalKind.classification,
        summaryZh: '短小定义型笔记 — 建议提取为 Concept',
        payload: <String, Object?>{
          'note_id': note.id,
          'kind': 'concept',
          'confidence': 0.5,
          'reason': '标题明确且正文短(< 120 字符),适合作 Concept primitive',
        },
        status: InboxProposalStatus.pending,
      );
    }
    return null;
  }

  static List<String> _decisionOptions(String text) {
    final firstLine = text.split('\n').first.trim();
    final separator =
        firstLine.contains(RegExp(r'\bvs\.?\b', caseSensitive: false))
        ? RegExp(r'\bvs\.?\b', caseSensitive: false)
        : firstLine.contains('还是')
        ? RegExp('还是')
        : firstLine.contains(RegExp(r'\bor\b', caseSensitive: false))
        ? RegExp(r'\bor\b', caseSensitive: false)
        : null;
    if (separator == null) return const <String>[];
    return firstLine
        .split(separator)
        .map((value) => value.replaceAll(RegExp(r'[？?。.]'), '').trim())
        .where((value) => value.length >= 2)
        .toSet()
        .take(5)
        .toList(growable: false);
  }

  static InboxProposal? _suggestTags(KnowledgeNote note) {
    if (note.tags.isNotEmpty) return null; // already user-tagged
    const dictionary = <String, List<String>>{
      'fire': ['fire', '财务自由', '退休', 'withdrawal', 'safe withdrawal'],
      'options': ['call', 'put', 'option', '期权', 'iv', 'covered'],
      'health': ['hrv', '睡眠', 'sleep', 'recovery', '心率'],
      'allocation': ['allocation', '配置', '资产配置', 'rebalance'],
      'tax': ['税', 'tax', 'gain', 'capital gain'],
      'mindset': ['mindset', '心态', '原则', '认知'],
    };
    final lower = '${note.title}\n${note.bodyMd}'.toLowerCase();
    final hits = <String>[];
    for (final entry in dictionary.entries) {
      for (final marker in entry.value) {
        if (lower.contains(marker)) {
          hits.add(entry.key);
          break;
        }
      }
    }
    if (hits.isEmpty) return null;
    return InboxProposal(
      kind: InboxProposalKind.tags,
      summaryZh: '建议加上 tags: ${hits.join("/")}',
      payload: <String, Object?>{
        'note_id': note.id,
        'tags': hits,
        'reason': '正文中出现 ${hits.join("/")} 相关关键词',
      },
      status: InboxProposalStatus.pending,
    );
  }

  static InboxProposal? _suggestLink(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
    String lowerCorpus,
  ) {
    if (decisions.isEmpty) return null;
    final matches = <KnowledgeDecision>[];
    for (final d in decisions) {
      final q = d.question.trim().toLowerCase();
      if (q.length < 6) continue;
      // Token overlap: at least two ≥3-char tokens of the question
      // appear verbatim in the note. Cheap and good enough for the
      // heuristic stage — LLM judge replaces this later.
      final tokens = q
          .split(RegExp(r'[\s/，。：；,;:]+'))
          .where((t) => t.length >= 3)
          .toSet();
      var overlap = 0;
      for (final t in tokens) {
        if (lowerCorpus.contains(t)) overlap++;
        if (overlap >= 2) break;
      }
      if (overlap >= 2) matches.add(d);
      if (matches.length >= 3) break;
    }
    if (matches.isEmpty) return null;
    return InboxProposal(
      kind: InboxProposalKind.linkToDecision,
      summaryZh: matches.length == 1
          ? '看起来和决策 "${matches.first.question}" 相关 — 建议关联'
          : '看起来和 ${matches.length} 条决策相关 — 建议关联',
      payload: <String, Object?>{
        'note_id': note.id,
        'related_decision_ids': matches
            .map((d) => d.id)
            .toList(growable: false),
        'reason': '正文与决策问题有 ≥ 2 个 token 重合',
      },
      status: InboxProposalStatus.pending,
    );
  }
}
