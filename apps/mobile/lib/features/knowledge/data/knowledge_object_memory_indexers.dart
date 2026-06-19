/// KnowledgeOS object → Memory indexers for the five non-Decision
/// types (`docs/knowledgeos-domain.md` §3 — "写一份,索引两次").
///
/// Decision has its own file because its payload / status semantics
/// are richer; the five types here share the same "subscribe-and-
/// reindex" shape and are bundled to make the surface honest about
/// how light each one is.
///
/// kind picked per §3 / Memory Layer semantics:
///
/// - Note        → episodic — captured moment, has a `createdAt` anchor
/// - Principle   → semantic — long-term worldview primitive
/// - Assumption  → semantic — falsifiable belief; carries `confidence`
/// - Concept     → semantic — definition / vocabulary node
/// - Experiment  → episodic — timeline event with a `startedAt` anchor
///
/// All five gate on `domainOptInsProvider.contains(DomainScope.knowledge)`
/// — same gate as the Decision indexer.
library;

import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../design_system/preferences/theme_preferences.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';
import 'knowledge_repository.dart';
import 'providers.dart';

// ── KnowledgeOS Memory sources (single catalogue) ──────────────────────────
// `MemoryRuntime.recall(source:)` is an exact match — there is no `know:*`
// wildcard — so every type's source string is declared here, and the
// dedupe / cross-type search tools iterate [kKnowledgeMemorySources].
// The Decision indexer lives in its own file but imports its source from
// here so this stays the one place a new type is registered.
const String kKnowledgeNoteMemorySource = 'know:notes';
const String kKnowledgePrincipleMemorySource = 'know:principles';
const String kKnowledgeAssumptionMemorySource = 'know:assumptions';
const String kKnowledgeConceptMemorySource = 'know:concepts';
const String kKnowledgeExperimentMemorySource = 'know:experiments';
const String kKnowledgeDecisionMemorySource = 'know:decisions';
const String kKnowledgeRoutineMemorySource = 'know:routines';

/// Every KnowledgeOS Memory source keyed by a short type token
/// (`docs/knowledgeos-domain.md` §15.3). Iterated by the dedupe /
/// cross-type search tools. Add a new type's source above and here.
const Map<String, String> kKnowledgeMemorySources = <String, String>{
  'note': kKnowledgeNoteMemorySource,
  'principle': kKnowledgePrincipleMemorySource,
  'assumption': kKnowledgeAssumptionMemorySource,
  'concept': kKnowledgeConceptMemorySource,
  'experiment': kKnowledgeExperimentMemorySource,
  'decision': kKnowledgeDecisionMemorySource,
  'routine': kKnowledgeRoutineMemorySource,
};

/// Knowledge types where a near-duplicate can be turned into a supported
/// `knowledge_merge` proposal. Routine rows are searchable, but excluded
/// from dedupe until they get a merge pointer and apply path.
const Map<String, String> kKnowledgeDedupeMemorySources = <String, String>{
  'note': kKnowledgeNoteMemorySource,
  'principle': kKnowledgePrincipleMemorySource,
  'assumption': kKnowledgeAssumptionMemorySource,
  'concept': kKnowledgeConceptMemorySource,
  'experiment': kKnowledgeExperimentMemorySource,
  'decision': kKnowledgeDecisionMemorySource,
};

String _truncate(String s, [int n = kKnowledgeExcerptMaxChars]) =>
    knowledgeExcerpt(s, max: n);

Future<void> _forgetMissingSourceIds(
  MemoryRuntime runtime, {
  required String ownerUserId,
  required String source,
  required Set<String> liveSourceIds,
}) {
  return runtime.forgetSourceExcept(
    ownerUserId: ownerUserId,
    source: source,
    keepSourceIds: liveSourceIds,
  );
}

/// Shared subscribe-then-reindex plumbing for every KnowledgeOS indexer
/// provider, Decision included (`docs/knowledgeos-domain.md` §3).
///
/// Each indexer used to repeat ~15 lines of identical Riverpod
/// boilerplate: opt-in gate → resolve repo/userId/runtime → re-entrance
/// guard → subscribe → reindex on emit → dispose. The varying parts
/// are only the stream factory and the reindex callback, so they're
/// the only parameters; everything else is enforced here.
void subscribeKnowledgeIndexer<T>(
  Ref ref, {
  required Stream<List<T>> Function(KnowledgeRepository repo, String userId)
  streamOf,
  required Future<void> Function(
    MemoryRuntime runtime,
    List<T> rows, {
    required String ownerUserId,
  })
  reindex,
}) {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.knowledge)) return;
  () async {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final runtime = await ref.read(memoryRuntimeProvider.future);
    var running = false;
    List<T>? pendingRows;
    final sub = streamOf(repo, userId).listen((rows) async {
      if (running) {
        pendingRows = rows;
        return;
      }
      running = true;
      try {
        var currentRows = rows;
        while (true) {
          await reindex(runtime, currentRows, ownerUserId: userId);
          final nextRows = pendingRows;
          pendingRows = null;
          if (nextRows == null) break;
          currentRows = nextRows;
        }
      } finally {
        running = false;
      }
    });
    ref.onDispose(sub.cancel);
  }();
}

// ── Notes ────────────────────────────────────────────────────────────────

Future<void> _reindexNotes(
  MemoryRuntime runtime,
  List<KnowledgeNote> notes, {
  required String ownerUserId,
  required String untitled,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgeNoteMemorySource,
    liveSourceIds: {for (final n in notes) n.id},
  );
  for (final n in notes) {
    final id = '$kKnowledgeNoteMemorySource:episodic:${n.id}';
    final summary = n.bodyMd.isEmpty
        ? n.title
        : '${n.title.isEmpty ? "(untitled)" : n.title}: ${_truncate(n.bodyMd)}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.episodic,
        ownerUserId: ownerUserId,
        scope: '*',
        source: kKnowledgeNoteMemorySource,
        sourceId: n.id,
        title: n.title.isEmpty ? untitled : n.title,
        summary: summary,
        payload: <String, Object?>{
          'body_md': n.bodyMd,
          'tags': n.tags,
          if (n.projectTag != null) 'project_tag': n.projectTag,
          if (n.sourceUrl != null) 'source_url': n.sourceUrl,
        },
        entities: <String>{
          'knowledge_note',
          n.id,
          ...n.tags.map((t) => 'tag:$t'),
        },
        importance: 0.5,
        confidence: 0.85,
        validFrom: n.createdAt.toUtc(),
        createdAt: n.createdAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeNoteMemoryIndexerProvider = Provider<void>((ref) {
  final l10n = _knowledgeIndexerL10n(ref.watch(localeProvider));
  subscribeKnowledgeIndexer<KnowledgeNote>(
    ref,
    streamOf: (r, uid) => r.watchNotes(ownerUserId: uid, limit: 200),
    reindex: (runtime, notes, {required ownerUserId}) => _reindexNotes(
      runtime,
      notes,
      ownerUserId: ownerUserId,
      untitled: l10n.knowledgeUntitled,
    ),
  );
});

AppLocalizations _knowledgeIndexerL10n(Locale? preferred) {
  final locale = preferred ?? PlatformDispatcher.instance.locale;
  final supported = locale.languageCode == 'zh'
      ? const Locale('zh')
      : const Locale('en');
  return lookupAppLocalizations(supported);
}

// ── Principles ───────────────────────────────────────────────────────────

Future<void> _reindexPrinciples(
  MemoryRuntime runtime,
  List<KnowledgePrinciple> ps, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgePrincipleMemorySource,
    liveSourceIds: {for (final p in ps) p.id},
  );
  for (final p in ps) {
    final id = '$kKnowledgePrincipleMemorySource:semantic:${p.id}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.semantic,
        ownerUserId: ownerUserId,
        scope: p.scope,
        source: kKnowledgePrincipleMemorySource,
        sourceId: p.id,
        title: p.statement,
        summary: p.rationaleMd.isEmpty
            ? p.statement
            : '${p.statement} — ${_truncate(p.rationaleMd)}',
        payload: <String, Object?>{
          'rationale_md': p.rationaleMd,
          'status': p.status.wire,
        },
        entities: <String>{'knowledge_principle', p.id},
        // Active principles outrank retired ones for recall.
        importance: switch (p.status) {
          PrincipleStatus.active => 0.9,
          PrincipleStatus.paused => 0.6,
          PrincipleStatus.retired => 0.4,
        },
        confidence: 0.95,
        validFrom: p.declaredAt.toUtc(),
        createdAt: p.declaredAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgePrincipleMemoryIndexerProvider = Provider<void>((ref) {
  subscribeKnowledgeIndexer<KnowledgePrinciple>(
    ref,
    streamOf: (r, uid) => r.watchPrinciples(ownerUserId: uid),
    reindex: _reindexPrinciples,
  );
});

// ── Assumptions ──────────────────────────────────────────────────────────

Future<void> _reindexAssumptions(
  MemoryRuntime runtime,
  List<KnowledgeAssumption> xs, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgeAssumptionMemorySource,
    liveSourceIds: {for (final a in xs) a.id},
  );
  for (final a in xs) {
    final id = '$kKnowledgeAssumptionMemorySource:semantic:${a.id}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.semantic,
        ownerUserId: ownerUserId,
        scope: a.scope,
        source: kKnowledgeAssumptionMemorySource,
        sourceId: a.id,
        title: a.statement,
        summary: a.statement,
        payload: <String, Object?>{
          'status': a.status.wire,
          'confidence': a.confidence,
          'evidence_ids': a.evidenceIds,
          if (a.lastVerifiedAt != null)
            'last_verified_at': a.lastVerifiedAt!.toUtc().toIso8601String(),
        },
        entities: <String>{'knowledge_assumption', a.id},
        // Map the user's own stated confidence directly. Falsified
        // assumptions stay in memory (so ContradictionAgent can still
        // see them) but with much lower importance.
        importance: switch (a.status) {
          AssumptionStatus.active => a.confidence,
          AssumptionStatus.weakened => a.confidence * 0.5,
          AssumptionStatus.falsified => 0.2,
          AssumptionStatus.retired => 0.2,
        },
        confidence: a.confidence,
        validFrom: a.declaredAt.toUtc(),
        createdAt: a.declaredAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeAssumptionMemoryIndexerProvider = Provider<void>((ref) {
  subscribeKnowledgeIndexer<KnowledgeAssumption>(
    ref,
    streamOf: (r, uid) => r.watchAssumptions(ownerUserId: uid),
    reindex: _reindexAssumptions,
  );
});

// ── Concepts ─────────────────────────────────────────────────────────────

Future<void> _reindexConcepts(
  MemoryRuntime runtime,
  List<KnowledgeConcept> cs, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgeConceptMemorySource,
    liveSourceIds: {for (final c in cs) c.id},
  );
  for (final c in cs) {
    final id = '$kKnowledgeConceptMemorySource:semantic:${c.id}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.semantic,
        ownerUserId: ownerUserId,
        scope: '*',
        source: kKnowledgeConceptMemorySource,
        sourceId: c.id,
        title: c.name,
        summary: c.summaryMd.isEmpty
            ? c.name
            : '${c.name}: ${_truncate(c.summaryMd)}',
        payload: <String, Object?>{
          'aliases': c.aliases,
          'summary_md': c.summaryMd,
          'related_concept_ids': c.relatedConceptIds,
        },
        entities: <String>{
          'knowledge_concept',
          c.id,
          ...c.aliases.map((a) => 'alias:$a'),
        },
        importance: 0.7,
        confidence: 0.9,
        validFrom: c.createdAt.toUtc(),
        createdAt: c.createdAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeConceptMemoryIndexerProvider = Provider<void>((ref) {
  subscribeKnowledgeIndexer<KnowledgeConcept>(
    ref,
    streamOf: (r, uid) => r.watchConcepts(ownerUserId: uid),
    reindex: _reindexConcepts,
  );
});

// ── Experiments ──────────────────────────────────────────────────────────

Future<void> _reindexExperiments(
  MemoryRuntime runtime,
  List<KnowledgeExperiment> xs, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgeExperimentMemorySource,
    liveSourceIds: {for (final e in xs) e.id},
  );
  for (final e in xs) {
    final id = '$kKnowledgeExperimentMemorySource:episodic:${e.id}';
    final body = e.methodMd.isEmpty
        ? e.hypothesis
        : '${e.hypothesis} — method: ${_truncate(e.methodMd)}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.episodic,
        ownerUserId: ownerUserId,
        scope: '*',
        source: kKnowledgeExperimentMemorySource,
        sourceId: e.id,
        title: e.hypothesis,
        summary: body,
        payload: <String, Object?>{
          'method_md': e.methodMd,
          'metrics': e.metrics,
          'status': e.status.wire,
          if (e.resultMd != null) 'result_md': e.resultMd,
          if (e.conclusionMd != null) 'conclusion_md': e.conclusionMd,
          if (e.targetAssumptionId != null)
            'target_assumption_id': e.targetAssumptionId,
          if (e.endedAt != null)
            'ended_at': e.endedAt!.toUtc().toIso8601String(),
        },
        entities: <String>{
          'knowledge_experiment',
          e.id,
          if (e.targetAssumptionId != null)
            'assumption:${e.targetAssumptionId}',
        },
        importance: switch (e.status) {
          ExperimentStatus.running => 0.8,
          ExperimentStatus.done => 0.85,
          ExperimentStatus.planned => 0.5,
          ExperimentStatus.abandoned => 0.4,
        },
        confidence: 0.85,
        validFrom: e.startedAt.toUtc(),
        createdAt: e.startedAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeExperimentMemoryIndexerProvider = Provider<void>((ref) {
  subscribeKnowledgeIndexer<KnowledgeExperiment>(
    ref,
    streamOf: (r, uid) => r.watchExperiments(ownerUserId: uid),
    reindex: _reindexExperiments,
  );
});

// ── Routines ─────────────────────────────────────────────────────────────

Future<void> _reindexRoutines(
  MemoryRuntime runtime,
  List<KnowledgeRoutine> routines, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgeRoutineMemorySource,
    liveSourceIds: {for (final r in routines) r.id},
  );
  for (final r in routines) {
    final id = '$kKnowledgeRoutineMemorySource:episodic:${r.id}';
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.episodic,
        ownerUserId: ownerUserId,
        scope: r.scope,
        source: kKnowledgeRoutineMemorySource,
        sourceId: r.id,
        title: r.statement,
        summary:
            '${r.statement} — every ${r.intervalDays} days; next due '
            '${r.nextDueAt.toUtc().toIso8601String()}',
        payload: <String, Object?>{
          'interval_days': r.intervalDays,
          'status': r.status.wire,
          'next_due_at': r.nextDueAt.toUtc().toIso8601String(),
          if (r.lastDoneAt != null)
            'last_done_at': r.lastDoneAt!.toUtc().toIso8601String(),
        },
        entities: <String>{'knowledge_routine', r.id, 'scope:${r.scope}'},
        importance: switch (r.status) {
          RoutineStatus.active => 0.65,
          RoutineStatus.paused => 0.35,
          RoutineStatus.archived => 0.25,
        },
        confidence: 0.9,
        validFrom: r.createdAt.toUtc(),
        createdAt: r.createdAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeRoutineMemoryIndexerProvider = Provider<void>((ref) {
  subscribeKnowledgeIndexer<KnowledgeRoutine>(
    ref,
    streamOf: (r, uid) => r.watchRoutines(ownerUserId: uid),
    reindex: _reindexRoutines,
  );
});
