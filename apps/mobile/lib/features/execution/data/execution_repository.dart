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

class ExecutionSearchHit {
  const ExecutionSearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.status,
  });

  final ExecutionEntryKind kind;
  final String id;
  final String title;
  final String status;
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

  Future<List<ExecutionSearchHit>> search({
    required String ownerUserId,
    required String query,
    int limit = 50,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const <ExecutionSearchHit>[];
    final escaped = normalized
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final pattern = '%$escaped%';
    final rows = await _db
        .customSelect(
          '''
SELECT 'action' AS kind, id, title, status
FROM execution_actions
WHERE owner_user_id = ? AND deleted_at IS NULL
  AND (LOWER(title) LIKE ? ESCAPE '\\' OR LOWER(note) LIKE ? ESCAPE '\\')
UNION ALL
SELECT 'project' AS kind, id, title, status
FROM execution_projects
WHERE owner_user_id = ? AND deleted_at IS NULL
  AND (LOWER(title) LIKE ? ESCAPE '\\' OR LOWER(description) LIKE ? ESCAPE '\\')
UNION ALL
SELECT 'commitment' AS kind, id, title, status
FROM execution_commitments
WHERE owner_user_id = ? AND deleted_at IS NULL
  AND (LOWER(title) LIKE ? ESCAPE '\\' OR LOWER(description) LIKE ? ESCAPE '\\')
ORDER BY title COLLATE NOCASE
LIMIT ?
''',
          variables: <Variable<Object>>[
            Variable<String>(ownerUserId),
            Variable<String>(pattern),
            Variable<String>(pattern),
            Variable<String>(ownerUserId),
            Variable<String>(pattern),
            Variable<String>(pattern),
            Variable<String>(ownerUserId),
            Variable<String>(pattern),
            Variable<String>(pattern),
            Variable<int>(limit.clamp(1, 200)),
          ],
          readsFrom: <TableInfo<Table, Object?>>{
            _db.executionActions,
            _db.executionProjects,
            _db.executionCommitments,
          },
        )
        .get();
    return rows
        .map(
          (row) => ExecutionSearchHit(
            kind: switch (row.read<String>('kind')) {
              'project' => ExecutionEntryKind.project,
              'commitment' => ExecutionEntryKind.commitment,
              _ => ExecutionEntryKind.action,
            },
            id: row.read<String>('id'),
            title: row.read<String>('title'),
            status: row.read<String>('status'),
          ),
        )
        .toList(growable: false);
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
  }
}
