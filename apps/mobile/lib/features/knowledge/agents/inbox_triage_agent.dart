/// `knowledge_inbox_triage` — async inbox triage agent
/// (`docs/knowledgeos-domain.md` §5 异步 triage flow + §7).
///
/// Scans `knowledge_notes` for entries the agent hasn't proposed against
/// yet (no row in `knowledge_inbox_triage`) and emits up to three
/// envelopes per note — classification / tags / link_to_decision —
/// directly into the side-table. The Review tab "AI 建议" card reads
/// the same side-table, so the agent's output lands in front of the
/// user without any additional plumbing.
///
/// Honours the §7 工程约束:
/// - Save path is **not** touched (the agent only reads notes + writes
///   to the never-sync triage table)
/// - Without an LLM the agent still runs — heuristic-only proposals so
///   the async triage UX is visible during dogfood. LLM-augmented
///   triage replaces these heuristics in the same agent slot once the
///   on-device LLM round-trip is wired (the propose_inbox_* tools
///   already accept LLM-shaped input).
/// - `dismissed` envelopes are preserved across runs (the side-table
///   merge in `_inbox_triage_support.persistEnvelope`).
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/auth/current_user.dart';
import '../data/inbox_triage_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

const String kKnowledgeInboxTriageAgentId = 'knowledge_inbox_triage';

/// Hard ceiling per run — keeps tick latency bounded when the user
/// drops a backlog into the inbox. The remaining notes triage on the
/// next 15-min tick.
const int kInboxTriageMaxNotesPerRun = 10;

class InboxTriageAgent implements Agent {
  const InboxTriageAgent();

  @override
  String get id => kKnowledgeInboxTriageAgentId;

  @override
  String get name => 'Inbox Triage';

  /// §7 "15min cadence". No preferred-hour anchor — runs whenever the
  /// runner ticks after the window opens.
  @override
  AgentSchedule get schedule => const AgentSchedule(
    interval: Duration(minutes: 15),
  );

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final triage = await ctx.ref.read(inboxTriageRepositoryProvider.future);

    final notes = await repo.listNotes(
      ownerUserId: ownerUserId,
      limit: 200,
    );
    final triagedIds = await triage.triagedNoteIds(ownerUserId: ownerUserId);
    final untriaged = notes
        .where((n) => !triagedIds.contains(n.id))
        .take(kInboxTriageMaxNotesPerRun)
        .toList(growable: false);

    final finished = DateTime.now().toUtc();
    if (untriaged.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kKnowledgeInboxTriageAgentId,
        startedAt: start,
        finishedAt: finished,
        reason: 'no untriaged notes',
      );
    }

    // Pull decisions once (used by link_to_decision heuristic) rather
    // than per-note — the candidate set is usually tiny.
    final decisions = await repo.listDecisions(
      ownerUserId: ownerUserId,
      limit: 200,
    );

    var emitted = 0;
    for (final note in untriaged) {
      final proposals = _heuristicProposals(note, decisions);
      if (proposals.isEmpty) {
        // Still record an empty row so we don't re-scan the same note
        // every 15 min — the absence of pending entries means "looked
        // at, nothing to suggest". The Review tab filters these out.
        await triage.upsert(
          InboxTriageRecord(
            noteId: note.id,
            ownerUserId: ownerUserId,
            lastTriagedAt: DateTime.now().toUtc(),
            proposals: const <InboxProposal>[],
          ),
        );
        continue;
      }
      await triage.upsert(
        InboxTriageRecord(
          noteId: note.id,
          ownerUserId: ownerUserId,
          lastTriagedAt: DateTime.now().toUtc(),
          proposals: proposals,
        ),
      );
      emitted += proposals.length;
    }

    final summary = emitted == 0
        ? '看了 ${untriaged.length} 条 note,没找到值得提议的'
        : '为 ${untriaged.length} 条 note 生成了 $emitted 条建议';
    return AgentRunResult(
      agentId: kKnowledgeInboxTriageAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: finished,
      summary: summary,
      payload: <String, Object?>{
        'scanned_notes': untriaged.length,
        'emitted_proposals': emitted,
      },
    );
  }

  /// MVP heuristic surface. Pure-Dart; no LLM dependency. Sufficient to
  /// exercise the async triage UI during dogfood; the LLM path lands
  /// once the on-device agent loop is plumbed.
  static List<InboxProposal> _heuristicProposals(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
  ) {
    final body = note.bodyMd;
    final lower = '${note.title}\n$body'.toLowerCase();
    final out = <InboxProposal>[];

    // --- classification --------------------------------------------------
    final classification = _classify(note);
    if (classification != null) out.add(classification);

    // --- tags ------------------------------------------------------------
    final tagSuggestion = _suggestTags(note);
    if (tagSuggestion != null) out.add(tagSuggestion);

    // --- link_to_decision -----------------------------------------------
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

    if (long && (hasQuestion || hasOptionsLanguage)) {
      return InboxProposal(
        kind: InboxProposalKind.classification,
        summaryZh: '看起来像在权衡某个选项 — 建议升级为 Decision draft',
        payload: <String, Object?>{
          'note_id': note.id,
          'kind': 'decision_candidate',
          'confidence': 0.6,
          'reason': '正文较长且包含 "对比 / 选项 / 应该 / ?" 类语言',
        },
        status: InboxProposalStatus.pending,
      );
    }
    // Single capitalised noun phrase / short body → concept_candidate.
    if (body.length < 120 && title.isNotEmpty && !hasQuestion) {
      return InboxProposal(
        kind: InboxProposalKind.classification,
        summaryZh: '短小定义型笔记 — 建议提取为 Concept',
        payload: <String, Object?>{
          'note_id': note.id,
          'kind': 'concept_candidate',
          'confidence': 0.5,
          'reason': '标题明确且正文短(< 120 字符),适合作 Concept primitive',
        },
        status: InboxProposalStatus.pending,
      );
    }
    return null;
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
        'related_decision_ids':
            matches.map((d) => d.id).toList(growable: false),
        'reason': '正文与决策问题有 ≥ 2 个 token 重合',
      },
      status: InboxProposalStatus.pending,
    );
  }
}
