import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

class KnowledgeProposalUndoRunner {
  const KnowledgeProposalUndoRunner({required this.repo, required this.stamp});

  final KnowledgeRepository repo;
  final Future<SyncMeta> Function() stamp;

  Future<void> run(Map<String, Object?> undoData) async {
    for (final row in knowledgeProposalMapList(undoData['delete'])) {
      final table = row['table'] as String?;
      final id = row['id'] as String?;
      if (table == null || id == null) continue;
      final meta = await stamp();
      if (table == 'knowledge_relations') {
        await repo.deleteRelation(id: id, sync: meta);
        continue;
      }
      await repo.deleteEntry(
        kind: knowledgeEntryKindForTable(table),
        id: id,
        sync: meta.copyWith(deletedAt: meta.updatedAt),
      );
    }

    for (final snapshot in knowledgeProposalMapList(undoData['restore'])) {
      await _restoreSnapshot(snapshot);
    }
  }

  Future<void> _restoreSnapshot(Map<String, Object?> snapshot) async {
    final table = snapshot['table'] as String?;
    if (table == null) {
      throw ProposalApplyException('KnowledgeOS undo snapshot missing table');
    }
    final meta = restoreKnowledgeSync(snapshot, await stamp());
    switch (table) {
      case 'knowledge_notes':
        await repo.upsertNote(knowledgeNoteFromSnapshot(snapshot, meta));
      case 'knowledge_principles':
        await repo.upsertPrinciple(
          knowledgePrincipleFromSnapshot(snapshot, meta),
        );
      case 'knowledge_assumptions':
        await repo.upsertAssumption(
          knowledgeAssumptionFromSnapshot(snapshot, meta),
        );
      case 'knowledge_decisions':
        await repo.upsertDecision(
          knowledgeDecisionFromSnapshot(snapshot, meta),
        );
      case 'knowledge_concepts':
        await repo.upsertConcept(knowledgeConceptFromSnapshot(snapshot, meta));
      case 'knowledge_experiments':
        await repo.upsertExperiment(
          knowledgeExperimentFromSnapshot(snapshot, meta),
        );
      case 'knowledge_routines':
        await repo.upsertRoutine(knowledgeRoutineFromSnapshot(snapshot, meta));
      case 'knowledge_relations':
        await repo.upsertRelation(
          knowledgeRelationFromSnapshot(snapshot, meta),
        );
      default:
        throw ProposalApplyException('unknown knowledge undo table: $table');
    }
  }
}

Map<String, Object?> knowledgeProposalUndoData({
  List<Map<String, Object?>> restore = const [],
  List<Map<String, Object?>> delete = const [],
}) => <String, Object?>{
  if (restore.isNotEmpty) 'restore': restore,
  if (delete.isNotEmpty) 'delete': delete,
};

Map<String, Object?> mergeKnowledgeProposalUndoData(
  Map<String, Object?>? base, {
  List<Map<String, Object?>> restore = const [],
  List<Map<String, Object?>> delete = const [],
}) {
  return knowledgeProposalUndoData(
    restore: [...knowledgeProposalMapList(base?['restore']), ...restore],
    delete: [...knowledgeProposalMapList(base?['delete']), ...delete],
  );
}

Map<String, Object?> knowledgeProposalDeleteRow(String table, String id) =>
    <String, Object?>{'table': table, 'id': id};

Iterable<Map<String, Object?>> knowledgeProposalMapList(Object? raw) sync* {
  if (raw is! List) return;
  for (final item in raw) {
    if (item is Map) {
      yield item.map((key, value) => MapEntry(key.toString(), value));
    }
  }
}

KnowledgeEntryKind knowledgeEntryKindForTable(String table) => switch (table) {
  'knowledge_notes' => KnowledgeEntryKind.note,
  'knowledge_principles' => KnowledgeEntryKind.principle,
  'knowledge_assumptions' => KnowledgeEntryKind.assumption,
  'knowledge_decisions' => KnowledgeEntryKind.decision,
  'knowledge_concepts' => KnowledgeEntryKind.concept,
  'knowledge_experiments' => KnowledgeEntryKind.experiment,
  'knowledge_routines' => KnowledgeEntryKind.routine,
  _ => throw ProposalApplyException('unknown knowledge undo table: $table'),
};

Map<String, Object?> snapshotKnowledgeNote(KnowledgeNote note) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_notes', note.id, note.sync),
      'title': note.title,
      'body_md': note.bodyMd,
      'source_url': note.sourceUrl,
      'tags': note.tags,
      'project_tag': note.projectTag,
      'created_at': note.createdAt.toUtc().toIso8601String(),
      'promoted_to_kind': note.promotedToKind,
      'promoted_to_id': note.promotedToId,
      'promoted_at': note.promotedAt?.toUtc().toIso8601String(),
      'merged_into_id': note.mergedIntoId,
    };

Map<String, Object?> snapshotKnowledgePrinciple(KnowledgePrinciple p) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_principles', p.id, p.sync),
      'statement': p.statement,
      'rationale_md': p.rationaleMd,
      'scope': p.scope,
      'status': p.status.wire,
      'declared_at': p.declaredAt.toUtc().toIso8601String(),
      'merged_into_id': p.mergedIntoId,
    };

Map<String, Object?> snapshotKnowledgeAssumption(KnowledgeAssumption a) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_assumptions', a.id, a.sync),
      'statement': a.statement,
      'confidence': a.confidence,
      'scope': a.scope,
      'evidence_ids': a.evidenceIds,
      'status': a.status.wire,
      'declared_at': a.declaredAt.toUtc().toIso8601String(),
      'last_verified_at': a.lastVerifiedAt?.toUtc().toIso8601String(),
      'merged_into_id': a.mergedIntoId,
    };

Map<String, Object?> snapshotKnowledgeDecision(KnowledgeDecision d) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_decisions', d.id, d.sync),
      'question': d.question,
      'options': [for (final option in d.options) option.toJson()],
      'selected_label': d.selectedLabel,
      'rationale_md': d.rationaleMd,
      'principle_ids': d.principleIds,
      'assumption_ids': d.assumptionIds,
      'expected_outcome': d.expectedOutcome,
      'review_date': d.reviewDate?.toUtc().toIso8601String(),
      'revisit_conditions': [
        for (final condition in d.revisitConditions) condition.toJson(),
      ],
      'actual_outcome_md': d.actualOutcomeMd,
      'status': d.status.wire,
      'superseded_by_decision_id': d.supersededByDecisionId,
      'context_snapshot': d.contextSnapshot,
      'decided_at': d.decidedAt.toUtc().toIso8601String(),
      'merged_into_id': d.mergedIntoId,
    };

Map<String, Object?> snapshotKnowledgeConcept(KnowledgeConcept c) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_concepts', c.id, c.sync),
      'name': c.name,
      'aliases': c.aliases,
      'summary_md': c.summaryMd,
      'related_concept_ids': c.relatedConceptIds,
      'created_at': c.createdAt.toUtc().toIso8601String(),
      'merged_into_id': c.mergedIntoId,
    };

Map<String, Object?> snapshotKnowledgeExperiment(KnowledgeExperiment e) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_experiments', e.id, e.sync),
      'hypothesis': e.hypothesis,
      'method_md': e.methodMd,
      'metrics': e.metrics,
      'status': e.status.wire,
      'result_md': e.resultMd,
      'conclusion_md': e.conclusionMd,
      'target_assumption_id': e.targetAssumptionId,
      'started_at': e.startedAt.toUtc().toIso8601String(),
      'ended_at': e.endedAt?.toUtc().toIso8601String(),
      'merged_into_id': e.mergedIntoId,
    };

Map<String, Object?> snapshotKnowledgeRelation(KnowledgeRelation relation) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_relations', relation.id, relation.sync),
      'from_kind': relation.fromKind,
      'from_id': relation.fromId,
      'relation': relation.relation.wire,
      'to_kind': relation.toKind,
      'to_id': relation.toId,
      'created_at': relation.createdAt.toUtc().toIso8601String(),
    };

Map<String, Object?> _snapshotBase(String table, String id, SyncMeta sync) =>
    <String, Object?>{
      'table': table,
      'id': id,
      if (sync.deletedAt != null)
        'deleted_at': sync.deletedAt!.toUtc().toIso8601String(),
    };

SyncMeta restoreKnowledgeSync(Map<String, Object?> snapshot, SyncMeta meta) {
  final deletedAt = _dateOrNull(snapshot['deleted_at']);
  return meta.copyWith(deletedAt: deletedAt == null ? null : meta.updatedAt);
}

KnowledgeNote knowledgeNoteFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgeNote(
  id: _string(s, 'id'),
  title: _string(s, 'title'),
  bodyMd: _string(s, 'body_md'),
  sourceUrl: s['source_url'] as String?,
  tags: _stringList(s['tags']),
  projectTag: s['project_tag'] as String?,
  createdAt: _date(s['created_at']),
  promotedToKind: s['promoted_to_kind'] as String?,
  promotedToId: s['promoted_to_id'] as String?,
  promotedAt: _dateOrNull(s['promoted_at']),
  mergedIntoId: s['merged_into_id'] as String?,
  sync: sync,
);

KnowledgePrinciple knowledgePrincipleFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgePrinciple(
  id: _string(s, 'id'),
  statement: _string(s, 'statement'),
  rationaleMd: _string(s, 'rationale_md'),
  scope: _string(s, 'scope'),
  status: PrincipleStatus.parse(_string(s, 'status')),
  declaredAt: _date(s['declared_at']),
  mergedIntoId: s['merged_into_id'] as String?,
  sync: sync,
);

KnowledgeAssumption knowledgeAssumptionFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgeAssumption(
  id: _string(s, 'id'),
  statement: _string(s, 'statement'),
  confidence: (s['confidence'] as num?)?.toDouble() ?? 0,
  scope: _string(s, 'scope'),
  evidenceIds: _stringList(s['evidence_ids']),
  status: AssumptionStatus.parse(_string(s, 'status')),
  declaredAt: _date(s['declared_at']),
  lastVerifiedAt: _dateOrNull(s['last_verified_at']),
  mergedIntoId: s['merged_into_id'] as String?,
  sync: sync,
);

KnowledgeDecision knowledgeDecisionFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgeDecision(
  id: _string(s, 'id'),
  question: _string(s, 'question'),
  options: [
    for (final raw in knowledgeProposalMapList(s['options']))
      DecisionOption.fromJson(raw),
  ],
  selectedLabel: _string(s, 'selected_label'),
  rationaleMd: _string(s, 'rationale_md'),
  principleIds: _stringList(s['principle_ids']),
  assumptionIds: _stringList(s['assumption_ids']),
  expectedOutcome: s['expected_outcome'] as String?,
  reviewDate: _dateOrNull(s['review_date']),
  revisitConditions: [
    for (final raw in knowledgeProposalMapList(s['revisit_conditions']))
      DecisionRevisitCondition.fromJson(raw),
  ],
  actualOutcomeMd: s['actual_outcome_md'] as String?,
  status: DecisionStatus.parse(_string(s, 'status')),
  supersededByDecisionId: s['superseded_by_decision_id'] as String?,
  contextSnapshot: _mapOrNull(s['context_snapshot']),
  decidedAt: _date(s['decided_at']),
  mergedIntoId: s['merged_into_id'] as String?,
  sync: sync,
);

KnowledgeConcept knowledgeConceptFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgeConcept(
  id: _string(s, 'id'),
  name: _string(s, 'name'),
  aliases: _stringList(s['aliases']),
  summaryMd: _string(s, 'summary_md'),
  relatedConceptIds: _stringList(s['related_concept_ids']),
  createdAt: _date(s['created_at']),
  mergedIntoId: s['merged_into_id'] as String?,
  sync: sync,
);

KnowledgeExperiment knowledgeExperimentFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgeExperiment(
  id: _string(s, 'id'),
  hypothesis: _string(s, 'hypothesis'),
  methodMd: _string(s, 'method_md'),
  metrics: _stringList(s['metrics']),
  status: ExperimentStatus.parse(_string(s, 'status')),
  resultMd: s['result_md'] as String?,
  conclusionMd: s['conclusion_md'] as String?,
  targetAssumptionId: s['target_assumption_id'] as String?,
  startedAt: _date(s['started_at']),
  endedAt: _dateOrNull(s['ended_at']),
  mergedIntoId: s['merged_into_id'] as String?,
  sync: sync,
);

KnowledgeRoutine knowledgeRoutineFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgeRoutine(
  id: _string(s, 'id'),
  statement: _string(s, 'statement'),
  intervalDays: (s['interval_days'] as num?)?.toInt() ?? 1,
  lastDoneAt: _dateOrNull(s['last_done_at']),
  nextDueAt: _date(s['next_due_at']),
  scope: _string(s, 'scope'),
  status: RoutineStatus.parse(_string(s, 'status')),
  createdAt: _date(s['created_at']),
  sync: sync,
);

KnowledgeRelation knowledgeRelationFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgeRelation(
  id: _string(s, 'id'),
  fromKind: _string(s, 'from_kind'),
  fromId: _string(s, 'from_id'),
  relation: KnowledgeRelationType.parse(_string(s, 'relation')),
  toKind: _string(s, 'to_kind'),
  toId: _string(s, 'to_id'),
  createdAt: _date(s['created_at']),
  sync: sync,
);

String _string(Map<String, Object?> map, String key) =>
    (map[key] as String?) ?? '';

List<String> _stringList(Object? raw) =>
    raw is List ? raw.whereType<String>().toList(growable: false) : const [];

Map<String, Object?>? _mapOrNull(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), value))
    : null;

DateTime _date(Object? raw) => DateTime.parse(raw as String).toUtc();

DateTime? _dateOrNull(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
