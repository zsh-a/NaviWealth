/// Canonical KnowledgeOS persistence: Notes, Decisions, and Relations.
library;

import 'package:drift/drift.dart';

import 'tables.dart' show SyncableTable;

@DataClassName('KnowledgeNoteRow')
class KnowledgeNotes extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get bodyMd => text()();
  TextColumn get sourceUrl => text().nullable()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get mergedIntoId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('KnowledgeDecisionRow')
class KnowledgeDecisions extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get question => text()();
  TextColumn get optionsJson => text().withDefault(const Constant('[]'))();
  TextColumn get selectedLabel => text().withDefault(const Constant(''))();
  TextColumn get rationaleMd => text().withDefault(const Constant(''))();
  TextColumn get expectedOutcome => text().nullable()();
  DateTimeColumn get reviewDate => dateTime().nullable()();
  TextColumn get revisitConditionsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get actualOutcomeMd => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get supersededByDecisionId => text().nullable()();
  DateTimeColumn get decidedAt => dateTime()();
  TextColumn get mergedIntoId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('KnowledgeRelationRow')
class KnowledgeRelations extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get fromKind => text()();
  TextColumn get fromId => text()();
  TextColumn get relation => text()();
  TextColumn get toKind => text()();
  TextColumn get toId => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

const List<String> knowledgeIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_knowledge_notes_owner_hlc '
      'ON knowledge_notes(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_notes_owner_created '
      'ON knowledge_notes(owner_user_id, created_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_decisions_owner_hlc '
      'ON knowledge_decisions(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_decisions_status_review '
      'ON knowledge_decisions(owner_user_id, status, review_date) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_relations_from '
      'ON knowledge_relations(owner_user_id, from_kind, from_id) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_relations_to '
      'ON knowledge_relations(owner_user_id, to_kind, to_id) '
      'WHERE deleted_at IS NULL',
];
