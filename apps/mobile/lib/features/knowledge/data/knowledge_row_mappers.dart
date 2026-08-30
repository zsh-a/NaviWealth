import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_source_url.dart';

KnowledgeNotesCompanion knowledgeNoteCompanion(KnowledgeNote note) =>
    KnowledgeNotesCompanion.insert(
      id: note.id,
      title: note.title,
      bodyMd: note.bodyMd,
      sourceUrl: Value(normalizeKnowledgeSourceUrl(note.sourceUrl)),
      tagsJson: Value(encodeStringList(note.tags)),
      createdAt: note.createdAt,
      mergedIntoId: Value(note.mergedIntoId),
      ownerUserId: note.sync.ownerUserId,
      updatedAt: note.sync.updatedAt,
      updatedByDevice: note.sync.updatedByDevice,
      hlc: note.sync.hlc,
      deletedAt: Value(note.sync.deletedAt),
    );

KnowledgeDecisionsCompanion knowledgeDecisionCompanion(KnowledgeDecision d) =>
    KnowledgeDecisionsCompanion.insert(
      id: d.id,
      question: d.question,
      optionsJson: Value(DecisionOption.encode(d.options)),
      selectedLabel: Value(d.selectedLabel),
      rationaleMd: Value(d.rationaleMd),
      expectedOutcome: Value(d.expectedOutcome),
      reviewDate: Value(d.reviewDate),
      revisitConditionsJson: Value(
        DecisionRevisitCondition.encode(d.revisitConditions),
      ),
      actualOutcomeMd: Value(d.actualOutcomeMd),
      status: Value(d.status.wire),
      supersededByDecisionId: Value(d.supersededByDecisionId),
      decidedAt: d.decidedAt,
      mergedIntoId: Value(d.mergedIntoId),
      ownerUserId: d.sync.ownerUserId,
      updatedAt: d.sync.updatedAt,
      updatedByDevice: d.sync.updatedByDevice,
      hlc: d.sync.hlc,
      deletedAt: Value(d.sync.deletedAt),
    );

KnowledgeRelationsCompanion knowledgeRelationCompanion(KnowledgeRelation r) =>
    KnowledgeRelationsCompanion.insert(
      id: r.id,
      fromKind: r.fromKind,
      fromId: r.fromId,
      relation: r.relation.wire,
      toKind: r.toKind,
      toId: r.toId,
      createdAt: r.createdAt,
      ownerUserId: r.sync.ownerUserId,
      updatedAt: r.sync.updatedAt,
      updatedByDevice: r.sync.updatedByDevice,
      hlc: r.sync.hlc,
      deletedAt: Value(r.sync.deletedAt),
    );

KnowledgeNote knowledgeNoteFromRow(KnowledgeNoteRow row) => KnowledgeNote(
  id: row.id,
  title: row.title,
  bodyMd: row.bodyMd,
  sourceUrl: row.sourceUrl,
  tags: decodeStringList(row.tagsJson),
  createdAt: row.createdAt,
  mergedIntoId: row.mergedIntoId,
  sync: _syncFromRow(
    ownerUserId: row.ownerUserId,
    updatedAt: row.updatedAt,
    updatedByDevice: row.updatedByDevice,
    hlc: row.hlc,
    deletedAt: row.deletedAt,
  ),
);

KnowledgeDecision knowledgeDecisionFromRow(KnowledgeDecisionRow row) =>
    KnowledgeDecision(
      id: row.id,
      question: row.question,
      options: DecisionOption.decode(row.optionsJson),
      selectedLabel: row.selectedLabel,
      rationaleMd: row.rationaleMd,
      expectedOutcome: row.expectedOutcome,
      reviewDate: row.reviewDate,
      revisitConditions: DecisionRevisitCondition.decode(
        row.revisitConditionsJson,
      ),
      actualOutcomeMd: row.actualOutcomeMd,
      status: DecisionStatus.parse(row.status),
      supersededByDecisionId: row.supersededByDecisionId,
      decidedAt: row.decidedAt,
      mergedIntoId: row.mergedIntoId,
      sync: _syncFromRow(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
        deletedAt: row.deletedAt,
      ),
    );

KnowledgeRelation knowledgeRelationFromRow(KnowledgeRelationRow row) =>
    KnowledgeRelation(
      id: row.id,
      fromKind: row.fromKind,
      fromId: row.fromId,
      relation: KnowledgeRelationType.parse(row.relation),
      toKind: row.toKind,
      toId: row.toId,
      createdAt: row.createdAt,
      sync: _syncFromRow(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
        deletedAt: row.deletedAt,
      ),
    );

SyncMeta _syncFromRow({
  required String ownerUserId,
  required DateTime updatedAt,
  required String updatedByDevice,
  required Hlc hlc,
  required DateTime? deletedAt,
}) => SyncMeta(
  ownerUserId: ownerUserId,
  updatedAt: updatedAt,
  updatedByDevice: updatedByDevice,
  hlc: hlc,
  deletedAt: deletedAt,
);
