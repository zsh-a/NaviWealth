import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

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

Map<String, Object?> _snapshotBase(String table, String id, SyncMeta sync) =>
    <String, Object?>{
      'table': table,
      'id': id,
      if (sync.deletedAt != null)
        'deleted_at': sync.deletedAt!.toUtc().toIso8601String(),
    };
