/// ExecutionOS repository.
///
/// Owns Drift access for actions, commitments, and progress entries. Callers
/// provide stamped sync metadata; the repository performs the write and
/// enqueues the changed row for sync.
library;

import 'package:drift/drift.dart' hide Column;

import '../../../core/persistence/app_database.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../core/sync/sync_meta.dart';
import '../domain/execution_models.dart';
import 'execution_row_mappers.dart';

part 'execution_repository_actions.dart';
part 'execution_repository_commitments.dart';
part 'execution_repository_helpers.dart';
part 'execution_repository_progress.dart';
part 'execution_repository_projects.dart';

enum ExecutionEntryKind {
  project('execution_projects'),
  action('execution_actions'),
  commitment('execution_commitments'),
  progressEntry('execution_progress_entries');

  const ExecutionEntryKind(this.tableName);
  final String tableName;
}

class ExecutionRepository
    with
        ExecutionProjectRepositoryMixin,
        ExecutionCommitmentRepositoryMixin,
        ExecutionActionRepositoryMixin,
        ExecutionProgressRepositoryMixin {
  ExecutionRepository({required AppDatabase db, required OutboxStore outbox})
    : _db = db,
      _outbox = outbox;

  @override
  final AppDatabase _db;
  @override
  final OutboxStore _outbox;

  static const String _projectsTable = 'execution_projects';
  static const String _actionsTable = 'execution_actions';
  static const String _commitmentsTable = 'execution_commitments';
  static const String _progressTable = 'execution_progress_entries';

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
  }
}
