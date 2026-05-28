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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../domain/knowledge_models.dart';
import 'providers.dart';

const String kKnowledgeNoteMemorySource = 'know:notes';
const String kKnowledgePrincipleMemorySource = 'know:principles';
const String kKnowledgeAssumptionMemorySource = 'know:assumptions';
const String kKnowledgeConceptMemorySource = 'know:concepts';
const String kKnowledgeExperimentMemorySource = 'know:experiments';

String _truncate(String s, [int n = 280]) =>
    s.length > n ? '${s.substring(0, n)}…' : s;

// ── Notes ────────────────────────────────────────────────────────────────

Future<void> _reindexNotes(
  MemoryRuntime runtime,
  List<KnowledgeNote> notes, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
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
        title: n.title.isEmpty ? '(untitled note)' : n.title,
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
  () async {
    final opt = await ref.read(core_auth.domainOptInsProvider.future);
    if (!opt.contains(DomainScope.knowledge)) return;
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final runtime = await ref.read(memoryRuntimeProvider.future);
    var running = false;
    final sub = repo
        .watchNotes(ownerUserId: userId, limit: 200)
        .listen((rows) async {
      if (running || rows.isEmpty) return;
      running = true;
      try {
        await _reindexNotes(runtime, rows, ownerUserId: userId);
      } finally {
        running = false;
      }
    });
    ref.onDispose(sub.cancel);
  }();
});

// ── Principles ───────────────────────────────────────────────────────────

Future<void> _reindexPrinciples(
  MemoryRuntime runtime,
  List<KnowledgePrinciple> ps, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
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
  () async {
    final opt = await ref.read(core_auth.domainOptInsProvider.future);
    if (!opt.contains(DomainScope.knowledge)) return;
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final runtime = await ref.read(memoryRuntimeProvider.future);
    var running = false;
    final sub = repo.watchPrinciples(ownerUserId: userId).listen((rows) async {
      if (running || rows.isEmpty) return;
      running = true;
      try {
        await _reindexPrinciples(runtime, rows, ownerUserId: userId);
      } finally {
        running = false;
      }
    });
    ref.onDispose(sub.cancel);
  }();
});

// ── Assumptions ──────────────────────────────────────────────────────────

Future<void> _reindexAssumptions(
  MemoryRuntime runtime,
  List<KnowledgeAssumption> xs, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
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
  () async {
    final opt = await ref.read(core_auth.domainOptInsProvider.future);
    if (!opt.contains(DomainScope.knowledge)) return;
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final runtime = await ref.read(memoryRuntimeProvider.future);
    var running = false;
    final sub =
        repo.watchAssumptions(ownerUserId: userId).listen((rows) async {
      if (running || rows.isEmpty) return;
      running = true;
      try {
        await _reindexAssumptions(runtime, rows, ownerUserId: userId);
      } finally {
        running = false;
      }
    });
    ref.onDispose(sub.cancel);
  }();
});

// ── Concepts ─────────────────────────────────────────────────────────────

Future<void> _reindexConcepts(
  MemoryRuntime runtime,
  List<KnowledgeConcept> cs, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
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
  () async {
    final opt = await ref.read(core_auth.domainOptInsProvider.future);
    if (!opt.contains(DomainScope.knowledge)) return;
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final runtime = await ref.read(memoryRuntimeProvider.future);
    var running = false;
    final sub = repo.watchConcepts(ownerUserId: userId).listen((rows) async {
      if (running || rows.isEmpty) return;
      running = true;
      try {
        await _reindexConcepts(runtime, rows, ownerUserId: userId);
      } finally {
        running = false;
      }
    });
    ref.onDispose(sub.cancel);
  }();
});

// ── Experiments ──────────────────────────────────────────────────────────

Future<void> _reindexExperiments(
  MemoryRuntime runtime,
  List<KnowledgeExperiment> xs, {
  required String ownerUserId,
}) async {
  final now = DateTime.now().toUtc();
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
  () async {
    final opt = await ref.read(core_auth.domainOptInsProvider.future);
    if (!opt.contains(DomainScope.knowledge)) return;
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final runtime = await ref.read(memoryRuntimeProvider.future);
    var running = false;
    final sub =
        repo.watchExperiments(ownerUserId: userId).listen((rows) async {
      if (running || rows.isEmpty) return;
      running = true;
      try {
        await _reindexExperiments(runtime, rows, ownerUserId: userId);
      } finally {
        running = false;
      }
    });
    ref.onDispose(sub.cancel);
  }();
});
