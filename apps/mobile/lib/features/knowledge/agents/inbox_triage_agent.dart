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
/// - Per-note proposals come from an [InboxTriageClassifier] seam
///   (§14.2). The provider injects the LLM-backed classifier when the
///   user has an active LLM profile and the pure-Dart heuristic
///   otherwise; the LLM path degrades silently to the same heuristic on
///   any failure, so the no-LLM (Web / no key) path is byte-for-byte
///   what it was before.
/// - `dismissed` envelopes are preserved across runs (the side-table
///   merge in `_inbox_triage_support.persistEnvelope`).
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/auth/current_user.dart';
import '../data/inbox_triage_classifier.dart' show InboxTriageClassifier;
import '../data/inbox_triage_repository.dart';
import '../data/providers.dart';

const String kKnowledgeInboxTriageAgentId = 'knowledge_inbox_triage';

/// Hard ceiling per run — keeps tick latency bounded when the user
/// drops a backlog into the inbox. The remaining notes triage on the
/// next 15-min tick.
const int kInboxTriageMaxNotesPerRun = 10;

class InboxTriageAgent implements Agent {
  /// [classifier] optionally pins the per-note proposal source (tests
  /// inject a fake here). In production it is left null and resolved per
  /// run from [inboxTriageClassifierProvider] via `ctx.ref` — that
  /// provider hands back the LLM-backed seam when a profile is
  /// configured and the pure-Dart heuristic otherwise. Resolving in
  /// `run()` (rather than at construction) keeps `knowledgeAgentsProvider`
  /// synchronous while still picking up the async LLM client.
  const InboxTriageAgent({this.classifier});

  final InboxTriageClassifier? classifier;

  @override
  String get id => kKnowledgeInboxTriageAgentId;

  @override
  String get name => 'Inbox Triage';

  /// §7 "15min cadence". No preferred-hour anchor — runs whenever the
  /// runner ticks after the window opens.
  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(minutes: 15));

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final triage = await ctx.ref.read(inboxTriageRepositoryProvider.future);
    // Test override wins; otherwise resolve the LLM-vs-heuristic seam.
    final pinned = classifier;
    final InboxTriageClassifier activeClassifier =
        pinned ?? await ctx.ref.read(inboxTriageClassifierProvider.future);

    final notes = await repo.listNotes(ownerUserId: ownerUserId, limit: 200);
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
      final proposals = await activeClassifier.triage(note, decisions);
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
}
