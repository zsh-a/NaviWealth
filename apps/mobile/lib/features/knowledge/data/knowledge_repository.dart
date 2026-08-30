/// KnowledgeOS repository for Notes, Decisions, and Relations.
library;

import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../domain/knowledge_models.dart';
import 'knowledge_row_mappers.dart';

part 'knowledge_repository_decisions.dart';
part 'knowledge_repository_merge.dart';
part 'knowledge_repository_merge_decisions.dart';
part 'knowledge_repository_merge_helpers.dart';
part 'knowledge_repository_merge_notes.dart';
part 'knowledge_repository_notes.dart';
part 'knowledge_repository_relations.dart';

const String _knowledgeNotesTable = 'knowledge_notes';
const String _knowledgeDecisionsTable = 'knowledge_decisions';
const String _knowledgeRelationsTable = 'knowledge_relations';

enum KnowledgeEntryKind {
  note('knowledge_notes'),
  decision('knowledge_decisions');

  const KnowledgeEntryKind(this.tableName);

  final String tableName;
}

typedef KnowledgeRowChanged = void Function(String tableName, String rowId);

class KnowledgeRepository
    with
        KnowledgeNotesRepositoryMixin,
        KnowledgeDecisionsRepositoryMixin,
        KnowledgeRelationsRepositoryMixin,
        KnowledgeRepositoryMerge {
  KnowledgeRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    KnowledgeRowChanged? onRowChanged,
  }) : _db = db,
       _outbox = outbox,
       _onRowChanged = onRowChanged;

  @override
  final AppDatabase _db;

  final OutboxStore _outbox;

  final KnowledgeRowChanged? _onRowChanged;

  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  /// Atomically creates a Decision and its directed source relation.
  ///
  /// The Note must still be live and owned by the Decision owner. Keeping both
  /// inserts and outbox rows in one transaction prevents a Decision from being
  /// created without the provenance link that motivated this workflow.
  Future<KnowledgeRelation> createDecisionFromNote({
    required String noteId,
    required KnowledgeDecision decision,
  }) async {
    final relation = KnowledgeRelation(
      id: knowledgeRelationId(
        fromKind: KnowledgeEntryKind.note.name,
        fromId: noteId,
        relation: KnowledgeRelationType.informs,
        toKind: KnowledgeEntryKind.decision.name,
        toId: decision.id,
      ),
      fromKind: KnowledgeEntryKind.note.name,
      fromId: noteId,
      relation: KnowledgeRelationType.informs,
      toKind: KnowledgeEntryKind.decision.name,
      toId: decision.id,
      createdAt: decision.decidedAt,
      sync: decision.sync,
    );
    await _db.transaction(() async {
      final note =
          await (_db.select(_db.knowledgeNotes)..where(
                (table) =>
                    table.id.equals(noteId) &
                    table.ownerUserId.equals(decision.sync.ownerUserId) &
                    table.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (note == null) {
        throw StateError('Cannot create a Decision from a missing Note.');
      }
      await _db
          .into(_db.knowledgeDecisions)
          .insert(
            knowledgeDecisionCompanion(decision),
            mode: InsertMode.insertOrReplace,
          );
      await _db
          .into(_db.knowledgeRelations)
          .insert(
            knowledgeRelationCompanion(relation),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(
        table: _knowledgeDecisionsTable,
        rowId: decision.id,
      );
      await _outbox.enqueue(
        table: _knowledgeRelationsTable,
        rowId: relation.id,
      );
    });
    _onRowChanged?.call(_knowledgeDecisionsTable, decision.id);
    _onRowChanged?.call(_knowledgeRelationsTable, relation.id);
    return relation;
  }

  @override
  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  }) async {
    await _db.transaction(() async {
      await _db.into(table).insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: tableName, rowId: rowId);
    });
    _onRowChanged?.call(tableName, rowId);
  }

  Future<void> deleteEntry({
    required KnowledgeEntryKind kind,
    required String id,
    required SyncMeta sync,
  }) async {
    final deletedAt = sync.deletedAt ?? sync.updatedAt;
    final relationIds = <String>[];
    await _db.transaction(() async {
      final relations =
          await (_db.select(_db.knowledgeRelations)..where(
                (table) =>
                    table.ownerUserId.equals(sync.ownerUserId) &
                    table.deletedAt.isNull() &
                    ((table.fromKind.equals(kind.name) &
                            table.fromId.equals(id)) |
                        (table.toKind.equals(kind.name) &
                            table.toId.equals(id))),
              ))
              .get();
      relationIds.addAll(relations.map((row) => row.id));

      final changed = await _db.customUpdate(
        '''
UPDATE ${kind.tableName}
SET updated_at = ?, updated_by_device = ?, hlc = ?, deleted_at = ?
WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL
''',
        variables: <Variable<Object>>[
          Variable<DateTime>(sync.updatedAt),
          Variable<String>(sync.updatedByDevice),
          Variable<String>(sync.hlc.toString()),
          Variable<DateTime>(deletedAt),
          Variable<String>(id),
          Variable<String>(sync.ownerUserId),
        ],
        updates: <TableInfo<Table, Object?>>{_tableFor(kind)},
      );
      if (changed > 0) {
        await _outbox.enqueue(table: kind.tableName, rowId: id);
      }

      for (final relation in relations) {
        await upsertRelation(
          KnowledgeRelation(
            id: relation.id,
            fromKind: relation.fromKind,
            fromId: relation.fromId,
            relation: KnowledgeRelationType.parse(relation.relation),
            toKind: relation.toKind,
            toId: relation.toId,
            createdAt: relation.createdAt,
            sync: sync.copyWith(deletedAt: deletedAt),
          ),
        );
      }
    });
    _onRowChanged?.call(kind.tableName, id);
    for (final relationId in relationIds) {
      _onRowChanged?.call(_knowledgeRelationsTable, relationId);
    }
  }

  TableInfo<Table, Object?> _tableFor(KnowledgeEntryKind kind) =>
      switch (kind) {
        KnowledgeEntryKind.note => _db.knowledgeNotes,
        KnowledgeEntryKind.decision => _db.knowledgeDecisions,
      };
}
