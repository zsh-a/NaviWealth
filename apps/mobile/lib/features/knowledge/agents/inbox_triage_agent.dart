/// `knowledge_inbox_triage` — async inbox triage agent
/// (`docs/domains/knowledgeos-domain.md` §5 异步 triage flow + §7).
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
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_l10n.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/inbox_triage_classifier.dart' show InboxTriageClassifier;
import '../data/inbox_triage_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

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
  const InboxTriageAgent({
    this.classifier,
    this.sourceReader = const RepositoryInboxTriageSourceReader(),
  });

  final InboxTriageClassifier? classifier;
  final InboxTriageSourceReader sourceReader;

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
    final l10n = agentL10n(ctx.ref);
    final triage = await ctx.ref.read(inboxTriageRepositoryProvider.future);
    // Test override wins; otherwise resolve the LLM-vs-heuristic seam.
    final pinned = classifier;
    final InboxTriageClassifier activeClassifier =
        pinned ?? await ctx.ref.read(inboxTriageClassifierProvider.future);

    final source = await sourceReader.read(ctx);
    final untriaged = source.untriagedNotes;

    final finished = DateTime.now().toUtc();
    if (untriaged.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kKnowledgeInboxTriageAgentId,
        startedAt: start,
        finishedAt: finished,
        reason: l10n.knowledgeAgentInboxSkipNoNotes,
        traceId: source.traceId,
      );
    }

    var emitted = 0;
    final artifactItems = <_InboxTriageArtifactItem>[];
    for (final note in untriaged) {
      final proposals = await activeClassifier.triage(note, source.decisions);
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
      artifactItems.add(_InboxTriageArtifactItem(note, proposals));
    }

    final summary = emitted == 0
        ? l10n.knowledgeAgentInboxSummaryNoSuggestions(untriaged.length)
        : l10n.knowledgeAgentInboxSummarySuggestions(emitted, untriaged.length);
    String? artifactId;
    if (emitted > 0) {
      final dayKey = AppFormatters.utcDayKey(start);
      artifactId = '$kKnowledgeInboxTriageAgentId:$dayKey';
      final artifactStore = await ctx.ref.read(
        agent_providers.agentArtifactStoreProvider.future,
      );
      await artifactStore.save(
        _buildArtifact(
          id: artifactId,
          ownerUserId: ownerUserId,
          createdAt: finished,
          summary: summary,
          scannedNotes: untriaged.length,
          emittedProposals: emitted,
          items: artifactItems,
          traceId: source.traceId,
          l10n: l10n,
        ),
      );
    }
    return AgentRunResult(
      agentId: kKnowledgeInboxTriageAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: finished,
      summary: summary,
      payload: <String, Object?>{
        'scanned_notes': untriaged.length,
        'emitted_proposals': emitted,
        if (source.traceId != null) 'trace_id': source.traceId,
      },
      artifactId: artifactId,
      traceId: source.traceId,
    );
  }

  AgentArtifact _buildArtifact({
    required String id,
    required String ownerUserId,
    required DateTime createdAt,
    required String summary,
    required int scannedNotes,
    required int emittedProposals,
    required List<_InboxTriageArtifactItem> items,
    required String? traceId,
    required AppLocalizations l10n,
  }) {
    final byKind = <InboxProposalKind, int>{};
    for (final item in items) {
      for (final proposal in item.proposals) {
        byKind.update(proposal.kind, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kKnowledgeInboxTriageAgentId,
      domain: 'knowledge',
      kind: AgentArtifactKind.review,
      severity: AgentArtifactSeverity.info,
      title: l10n.knowledgeAgentInboxArtifactTitle,
      summary: summary,
      insights: <AgentInsight>[
        AgentInsight(
          title: l10n.knowledgeAgentInboxInsightSuggestionsTitle,
          body: l10n.knowledgeAgentInboxInsightSuggestionsBody(
            emittedProposals,
            emittedProposals == 1 ? '' : 's',
            items.length,
            items.length == 1 ? '' : 's',
          ),
          payload: <String, Object?>{
            'scanned_notes': scannedNotes,
            'emitted_proposals': emittedProposals,
            'notes_with_suggestions': items.length,
          },
        ),
        for (final entry in byKind.entries)
          AgentInsight(
            title: _proposalKindLabel(l10n, entry.key),
            body: l10n.knowledgeAgentInboxInsightKindBody(
              entry.value,
              entry.value == 1
                  ? l10n.knowledgeAgentInboxProposalSuggestionSingular
                  : l10n.knowledgeAgentInboxProposalSuggestionPlural,
            ),
            payload: <String, Object?>{
              'proposal_kind': entry.key.wire,
              'count': entry.value,
            },
          ),
      ],
      evidence: <AgentEvidenceRef>[
        for (final item in items)
          AgentEvidenceRef(
            type: 'knowledge_note',
            id: item.note.id,
            label: item.note.title.isEmpty
                ? l10n.knowledgeAgentInboxUntitledNote
                : item.note.title,
            payload: <String, Object?>{
              'proposal_count': item.proposals.length,
              'proposal_kinds': item.proposals
                  .map((proposal) => proposal.kind.wire)
                  .toList(growable: false),
            },
          ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'open_object',
          label: l10n.knowledgeAgentInboxAction,
          intent: kKnowledgeReviewDueItemsIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
        ),
      ],
      traceId: traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 7)),
    );
  }
}

class _InboxTriageArtifactItem {
  const _InboxTriageArtifactItem(this.note, this.proposals);

  final KnowledgeNote note;
  final List<InboxProposal> proposals;
}

String _proposalKindLabel(AppLocalizations l10n, InboxProposalKind kind) =>
    switch (kind) {
      InboxProposalKind.classification =>
        l10n.knowledgeAgentInboxProposalClassification,
      InboxProposalKind.tags => l10n.knowledgeAgentInboxProposalTags,
      InboxProposalKind.linkToDecision =>
        l10n.knowledgeAgentInboxProposalDecisionLinks,
    };

abstract class InboxTriageSourceReader {
  Future<InboxTriageSourceSnapshot> read(AgentContext ctx);
}

class RepositoryInboxTriageSourceReader implements InboxTriageSourceReader {
  const RepositoryInboxTriageSourceReader();

  @override
  Future<InboxTriageSourceSnapshot> read(AgentContext ctx) async {
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final triage = await ctx.ref.read(inboxTriageRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final notes = await repo.listNotes(ownerUserId: ownerUserId, limit: 200);
    final triagedIds = await triage.triagedNoteIds(ownerUserId: ownerUserId);
    final untriaged = notes
        .where((n) => !triagedIds.contains(n.id))
        .take(kInboxTriageMaxNotesPerRun)
        .toList(growable: false);
    final decisions = await repo.listDecisions(
      ownerUserId: ownerUserId,
      limit: 200,
    );
    return InboxTriageSourceSnapshot(
      untriagedNotes: untriaged,
      decisions: decisions,
    );
  }
}

class FrbInboxTriageSourceReader implements InboxTriageSourceReader {
  const FrbInboxTriageSourceReader({
    required AgentRuntimeEffectPlanBinding runtime,
    this.fallback = const RepositoryInboxTriageSourceReader(),
  }) : _runtime = runtime;

  final AgentRuntimeEffectPlanBinding _runtime;
  final InboxTriageSourceReader fallback;

  @override
  Future<InboxTriageSourceSnapshot> read(AgentContext ctx) async {
    return _runtime.readFromEffectPlan(
      effectPlan: const <AgentRuntimeEffect>[
        AgentRuntimeEffect.tool(
          name: 'list_inbox_triage_candidates',
          input: <String, Object?>{
            'limit': kInboxTriageMaxNotesPerRun,
            'scan_limit': 200,
          },
        ),
        AgentRuntimeEffect.tool(
          name: 'list_triage_decisions',
          input: <String, Object?>{'limit': 200},
        ),
      ],
      maxEffectSteps: 2,
      fallback: () => fallback.read(ctx),
      decode: (stepRun) async {
        final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
        return inboxTriageSourceSnapshotFromTerminalStep(
          stepRun.terminalStep,
          ownerUserId: ownerUserId,
          traceId: stepRun.traceId,
        );
      },
    );
  }
}

class InboxTriageSourceSnapshot {
  const InboxTriageSourceSnapshot({
    required this.untriagedNotes,
    required this.decisions,
    this.traceId,
  });

  final List<KnowledgeNote> untriagedNotes;
  final List<KnowledgeDecision> decisions;
  final String? traceId;
}

InboxTriageSourceSnapshot? inboxTriageSourceSnapshotFromTerminalStep(
  Map<String, Object?> step, {
  required String ownerUserId,
  String? traceId,
}) {
  final byTool = agentRuntimeTerminalEffectResultsByToolName(step);
  final notes = inboxTriageNotesFromToolResult(
    byTool['list_inbox_triage_candidates'],
    ownerUserId: ownerUserId,
  );
  final decisions = inboxTriageDecisionsFromToolResult(
    byTool['list_triage_decisions'],
    ownerUserId: ownerUserId,
  );
  if (notes == null || decisions == null) return null;
  return InboxTriageSourceSnapshot(
    untriagedNotes: notes,
    decisions: decisions,
    traceId: traceId,
  );
}

List<KnowledgeNote>? inboxTriageNotesFromToolResult(
  Map<String, Object?>? result, {
  required String ownerUserId,
}) {
  final rawNotes = result?['notes'];
  if (rawNotes is! List) return null;
  final out = <KnowledgeNote>[];
  for (final raw in rawNotes) {
    final note = _asObject(raw);
    final id = note?['id'];
    final title = note?['title'];
    final body = note?['body_md'];
    final createdAt = DateTime.tryParse((note?['created_at'] as String?) ?? '');
    if (id is! String || title is! String || body is! String) return null;
    out.add(
      KnowledgeNote(
        id: id,
        title: title,
        bodyMd: body,
        tags: _stringList(note?['tags']),
        projectTag: note?['project_tag'] as String?,
        createdAt:
            createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        sync: _syntheticSync(ownerUserId),
      ),
    );
  }
  return out;
}

List<KnowledgeDecision>? inboxTriageDecisionsFromToolResult(
  Map<String, Object?>? result, {
  required String ownerUserId,
}) {
  final rawDecisions = result?['decisions'];
  if (rawDecisions is! List) return null;
  final out = <KnowledgeDecision>[];
  for (final raw in rawDecisions) {
    final decision = _asObject(raw);
    final id = decision?['id'];
    final question = decision?['question'];
    final selected = decision?['selected'];
    final status = decision?['status'];
    final decidedAt = DateTime.tryParse(
      (decision?['decided_at'] as String?) ?? '',
    );
    if (id is! String || question is! String) return null;
    out.add(
      KnowledgeDecision(
        id: id,
        question: question,
        options: const <DecisionOption>[],
        selectedLabel: selected is String ? selected : '',
        rationaleMd: '',
        principleIds: const <String>[],
        assumptionIds: const <String>[],
        status: status is String
            ? DecisionStatus.parse(status)
            : DecisionStatus.active,
        decidedAt:
            decidedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        sync: _syntheticSync(ownerUserId),
      ),
    );
  }
  return out;
}

Map<String, Object?>? _asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

SyncMeta _syntheticSync(String ownerUserId) {
  return SyncMeta(
    ownerUserId: ownerUserId,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedByDevice: 'frb-agent-runtime',
    hlc: Hlc.zero('frb-agent-runtime'),
  );
}
