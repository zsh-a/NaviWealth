/// ExecutionOS Drift tables.
///
/// Action is the lightweight personal todo / next-action primitive. Plan is the
/// only grouping primitive; its horizon expresses short delivery work or an
/// ongoing focus without introducing a second hierarchy. ProgressEntry records
/// updates, blockers, scope changes, and completion notes.
library;

import 'package:drift/drift.dart';

import 'tables.dart' show SyncableTable;

@DataClassName('ExecutionPlanRow')
class ExecutionPlans extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get horizon => text().withDefault(const Constant('open'))();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get sourceDomain => text().nullable()();
  TextColumn get sourceRowFamily => text().nullable()();
  TextColumn get sourceRowId => text().nullable()();
  TextColumn get sourceLabelSnapshot => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ExecutionActionRow')
class ExecutionActions extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('todo'))();
  TextColumn get priority => text().withDefault(const Constant('normal'))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  DateTimeColumn get scheduledFor => dateTime().nullable()();
  TextColumn get planId => text().nullable()();
  TextColumn get sourceDomain => text().nullable()();
  TextColumn get sourceRowFamily => text().nullable()();
  TextColumn get sourceRowId => text().nullable()();
  TextColumn get sourceLabelSnapshot => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ExecutionProgressEntryRow')
class ExecutionProgressEntries extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get actionId => text().nullable()();
  TextColumn get planId => text().nullable()();
  TextColumn get kind => text().withDefault(const Constant('checkin'))();
  TextColumn get note => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

const List<String> executionIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_execution_plans_owner_hlc '
      'ON execution_plans(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_execution_plans_status '
      'ON execution_plans(owner_user_id, status, target_date) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_execution_actions_owner_hlc '
      'ON execution_actions(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_execution_actions_today '
      'ON execution_actions(owner_user_id, status, scheduled_for, due_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_execution_actions_project '
      'ON execution_actions(owner_user_id, plan_id, status) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_execution_progress_owner_hlc '
      'ON execution_progress_entries(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_execution_progress_created '
      'ON execution_progress_entries(owner_user_id, created_at DESC) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_execution_progress_plan '
      'ON execution_progress_entries(owner_user_id, plan_id, created_at DESC) '
      'WHERE deleted_at IS NULL',
];
