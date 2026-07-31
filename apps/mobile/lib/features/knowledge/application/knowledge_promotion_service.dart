import 'package:naviwealth/core/sync/sync_meta.dart';

import '../data/capture_kind.dart';
import '../data/knowledge_repository.dart';
import '../domain/knowledge_models.dart';

final class KnowledgePromotionResult {
  const KnowledgePromotionResult({required this.kind, required this.id});

  final KnowledgeEntryKind kind;
  final String id;
}

/// Promotes raw Notes into first-class KnowledgeOS objects.
///
/// The source Note is retained as provenance and archived from normal Note
/// queries by the repository's atomic promotion write.
final class KnowledgePromotionService {
  KnowledgePromotionService({
    required this.repository,
    required this.ownerUserId,
    required this.stamp,
  });

  final KnowledgeRepository repository;
  final String ownerUserId;
  final Future<SyncMeta> Function() stamp;

  Future<KnowledgePromotionResult> promoteClassification({
    required KnowledgeNote note,
    required String classification,
    List<String> decisionOptions = const <String>[],
    String? expectedOutcome,
  }) async {
    return switch (classification) {
      'decision' => promoteToDecision(
        note,
        options: decisionOptions,
        expectedOutcome: expectedOutcome,
      ),
      'concept' => promoteToConcept(note),
      _ => throw StateError(
        'unsupported knowledge promotion classification: $classification',
      ),
    };
  }

  Future<KnowledgePromotionResult> promoteToDecision(
    KnowledgeNote note, {
    List<String> options = const <String>[],
    String? expectedOutcome,
  }) async {
    final normalizedOptions = options
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedOptions.length < 2) {
      throw StateError('decision promotion requires at least two options');
    }
    final existing = await _current(note);
    final prior = _priorResult(existing, KnowledgeEntryKind.decision);
    if (prior != null) return prior;
    final decisionSync = await stamp();
    final noteSync = await stamp();
    final id = knowledgePromotionTargetId(
      KnowledgeEntryKind.decision,
      existing.id,
    );
    final question = _headline(existing);
    final decision = KnowledgeDecision(
      id: id,
      question: question,
      options: normalizedOptions
          .map((label) => DecisionOption(label: label))
          .toList(growable: false),
      selectedLabel: '',
      rationaleMd: existing.bodyMd,
      principleIds: const <String>[],
      assumptionIds: const <String>[],
      expectedOutcome: expectedOutcome,
      status: DecisionStatus.draft,
      decidedAt: decisionSync.updatedAt,
      sync: decisionSync,
    );
    final promotedId = await repository.promoteNoteToDecision(
      source: existing,
      decision: decision,
      noteSync: noteSync,
    );
    return KnowledgePromotionResult(
      kind: KnowledgeEntryKind.decision,
      id: promotedId,
    );
  }

  Future<KnowledgePromotionResult> promoteToConcept(KnowledgeNote note) async {
    final existing = await _current(note);
    final prior = _priorResult(existing, KnowledgeEntryKind.concept);
    if (prior != null) return prior;
    final conceptSync = await stamp();
    final noteSync = await stamp();
    final id = knowledgePromotionTargetId(
      KnowledgeEntryKind.concept,
      existing.id,
    );
    final concept = KnowledgeConcept(
      id: id,
      name: _headline(existing),
      aliases: const <String>[],
      summaryMd: existing.bodyMd,
      relatedConceptIds: const <String>[],
      createdAt: conceptSync.updatedAt,
      sync: conceptSync,
    );
    final promotedId = await repository.promoteNoteToConcept(
      source: existing,
      concept: concept,
      noteSync: noteSync,
    );
    return KnowledgePromotionResult(
      kind: KnowledgeEntryKind.concept,
      id: promotedId,
    );
  }

  Future<KnowledgePromotionResult> promoteToPrinciple(
    KnowledgeNote note, {
    String scope = '*',
  }) async {
    final existing = await _current(note);
    final prior = _priorResult(existing, KnowledgeEntryKind.principle);
    if (prior != null) return prior;
    final targetSync = await stamp();
    final noteSync = await stamp();
    final principle = KnowledgePrinciple(
      id: knowledgePromotionTargetId(KnowledgeEntryKind.principle, existing.id),
      statement: _headline(existing),
      rationaleMd: existing.bodyMd,
      scope: scope,
      status: PrincipleStatus.active,
      declaredAt: targetSync.updatedAt,
      sync: targetSync,
    );
    final id = await repository.promoteNoteToPrinciple(
      source: existing,
      principle: principle,
      noteSync: noteSync,
    );
    return KnowledgePromotionResult(kind: KnowledgeEntryKind.principle, id: id);
  }

  Future<KnowledgePromotionResult> promoteToAssumption(
    KnowledgeNote note, {
    required double confidence,
    String scope = '*',
  }) async {
    if (confidence < 0 || confidence > 1) {
      throw StateError('assumption confidence must be between 0 and 1');
    }
    final existing = await _current(note);
    final prior = _priorResult(existing, KnowledgeEntryKind.assumption);
    if (prior != null) return prior;
    final targetSync = await stamp();
    final noteSync = await stamp();
    final assumption = KnowledgeAssumption(
      id: knowledgePromotionTargetId(
        KnowledgeEntryKind.assumption,
        existing.id,
      ),
      statement: _headline(existing),
      confidence: confidence,
      scope: scope,
      evidenceIds: <String>[existing.id],
      status: AssumptionStatus.active,
      declaredAt: targetSync.updatedAt,
      sync: targetSync,
    );
    final id = await repository.promoteNoteToAssumption(
      source: existing,
      assumption: assumption,
      noteSync: noteSync,
    );
    return KnowledgePromotionResult(
      kind: KnowledgeEntryKind.assumption,
      id: id,
    );
  }

  Future<KnowledgePromotionResult> promoteToExperiment(
    KnowledgeNote note, {
    required List<String> metrics,
    required String method,
  }) async {
    final normalizedMetrics = metrics
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedMetrics.isEmpty || method.trim().isEmpty) {
      throw StateError('experiment promotion requires method and metrics');
    }
    final existing = await _current(note);
    final prior = _priorResult(existing, KnowledgeEntryKind.experiment);
    if (prior != null) return prior;
    final targetSync = await stamp();
    final noteSync = await stamp();
    final experiment = KnowledgeExperiment(
      id: knowledgePromotionTargetId(
        KnowledgeEntryKind.experiment,
        existing.id,
      ),
      hypothesis: _headline(existing),
      methodMd: method.trim(),
      metrics: normalizedMetrics,
      status: ExperimentStatus.planned,
      startedAt: targetSync.updatedAt,
      sync: targetSync,
    );
    final id = await repository.promoteNoteToExperiment(
      source: existing,
      experiment: experiment,
      noteSync: noteSync,
    );
    return KnowledgePromotionResult(
      kind: KnowledgeEntryKind.experiment,
      id: id,
    );
  }

  Future<KnowledgePromotionResult> promoteToRoutine(
    KnowledgeNote note, {
    required int intervalDays,
    String? statement,
    String scope = '*',
    DateTime? nextDueAt,
  }) async {
    final existing = await _current(note);
    final prior = _priorResult(existing, KnowledgeEntryKind.routine);
    if (prior != null) return prior;
    final targetSync = await stamp();
    final noteSync = await stamp();
    final normalizedInterval = intervalDays.clamp(1, 3650);
    final routine = KnowledgeRoutine(
      id: knowledgePromotionTargetId(KnowledgeEntryKind.routine, existing.id),
      statement: statement?.trim().isNotEmpty == true
          ? statement!.trim()
          : _headline(existing),
      intervalDays: normalizedInterval,
      nextDueAt:
          nextDueAt?.toUtc() ??
          targetSync.updatedAt.add(Duration(days: normalizedInterval)),
      scope: scope,
      status: RoutineStatus.active,
      createdAt: targetSync.updatedAt,
      sync: targetSync,
    );
    final id = await repository.promoteNoteToRoutine(
      source: existing,
      routine: routine,
      noteSync: noteSync,
    );
    return KnowledgePromotionResult(kind: KnowledgeEntryKind.routine, id: id);
  }

  Future<KnowledgePromotionResult> promoteCapture({
    required KnowledgeNote note,
    required CaptureKind kind,
    String? scope,
    int? intervalDays,
    String? statement,
    DateTime? nextDueAt,
    List<String> decisionOptions = const <String>[],
    String? expectedOutcome,
    double? assumptionConfidence,
    List<String> experimentMetrics = const <String>[],
    String? experimentMethod,
  }) => switch (kind) {
    CaptureKind.decision => promoteToDecision(
      note,
      options: decisionOptions,
      expectedOutcome: expectedOutcome,
    ),
    CaptureKind.principle => promoteToPrinciple(note, scope: scope ?? '*'),
    CaptureKind.assumption => promoteToAssumption(
      note,
      confidence:
          assumptionConfidence ??
          (throw StateError('assumption promotion requires confidence')),
      scope: scope ?? '*',
    ),
    CaptureKind.concept => promoteToConcept(note),
    CaptureKind.experiment => promoteToExperiment(
      note,
      metrics: experimentMetrics,
      method:
          experimentMethod ??
          (throw StateError('experiment promotion requires method')),
    ),
    CaptureKind.routine => promoteToRoutine(
      note,
      intervalDays: intervalDays ?? 180,
      statement: statement,
      scope: scope ?? '*',
      nextDueAt: nextDueAt,
    ),
    CaptureKind.note => throw StateError('note is not a typed Note promotion'),
  };

  Future<KnowledgeNote> _current(KnowledgeNote note) async {
    final current = await repository.findNote(
      ownerUserId: ownerUserId,
      id: note.id,
    );
    if (current == null) throw StateError('note ${note.id} no longer exists');
    return current;
  }

  KnowledgePromotionResult? _priorResult(
    KnowledgeNote note,
    KnowledgeEntryKind expected,
  ) {
    if (!note.isPromoted) return null;
    if (note.promotedToKind != expected.name) {
      throw StateError(
        'note ${note.id} is already promoted to ${note.promotedToKind}',
      );
    }
    return KnowledgePromotionResult(kind: expected, id: note.promotedToId!);
  }

  String _headline(KnowledgeNote note) {
    final title = note.title.trim();
    if (title.isNotEmpty) return title;
    for (final line in note.bodyMd.split('\n')) {
      final value = line.trim();
      if (value.isNotEmpty) return value;
    }
    return 'Untitled';
  }
}

String knowledgePromotionTargetId(KnowledgeEntryKind kind, String noteId) =>
    'promotion:${kind.name}:$noteId';
