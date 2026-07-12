import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../auth/domain_scope.dart';
import '../persistence/app_database.dart';
import '../sync/sync_table_registry.dart';

/// One physical table participating in a logical domain data resource.
///
/// Table names are registered by application code, never accepted from user
/// input. [ownerScoped] keeps maintenance actions isolated to the active user.
class DataTableSpec {
  const DataTableSpec({
    required this.table,
    this.ownerScoped = false,
    this.hasTombstones = false,
    this.preserveOnReset = false,
  }) : assert(table != '');

  final String table;
  final bool ownerScoped;
  final bool hasTombstones;
  final bool preserveOnReset;
}

/// Data-management contribution owned by one LifeOS domain.
///
/// [sourceTables] are user-authored source of truth. They may only be removed
/// through an explicit domain reset. [cacheTables] contain local, re-creatable
/// data and can be cleared independently without touching sync.
class DomainDataManagementSpec {
  const DomainDataManagementSpec({
    required this.scope,
    required this.label,
    required this.sourceTables,
    this.cacheTables = const <DataTableSpec>[],
  });

  final DomainScope scope;
  final String label;
  final List<DataTableSpec> sourceTables;
  final List<DataTableSpec> cacheTables;
}

/// Read model displayed by Settings → Data & Storage.
class DomainDataSnapshot {
  const DomainDataSnapshot({
    required this.scope,
    required this.label,
    required this.sourceRows,
    required this.deletedRows,
    required this.cacheRows,
    required this.sourceTableCount,
    required this.cacheTableCount,
  });

  final DomainScope scope;
  final String label;
  final int sourceRows;
  final int deletedRows;
  final int cacheRows;
  final int sourceTableCount;
  final int cacheTableCount;
}

/// Device-local data shared by multiple domains, plus SQLite space usage.
class SharedDataSnapshot {
  const SharedDataSnapshot({
    required this.chatRows,
    required this.aiRows,
    required this.memoryRows,
    required this.agentRows,
    required this.databaseBytes,
    required this.reclaimableBytes,
  });

  final int chatRows;
  final int aiRows;
  final int memoryRows;
  final int agentRows;
  final int databaseBytes;
  final int reclaimableBytes;

  int get historyRows => chatRows + aiRows + memoryRows + agentRows;
}

/// Builds source-table metadata from the sync registry SSOT.
List<DataTableSpec> syncDataTablesForPrefix(String prefix) =>
    List<DataTableSpec>.unmodifiable(<DataTableSpec>[
      for (final registration in kSyncTableRegistrations)
        if (registration.domainPrefix == prefix)
          DataTableSpec(
            table: registration.table,
            ownerScoped: registration.ownerScoped,
            // Non-owner-scoped reference tables (currently fx_rates) do not
            // use SyncableTable and therefore have no deleted_at column.
            hasTombstones: registration.ownerScoped,
          ),
    ]);

/// Executes domain-neutral inspection and safe cache maintenance.
class DataManagementService {
  DataManagementService({
    required AppDatabase database,
    required String ownerUserId,
    required List<DomainDataManagementSpec> specs,
    Map<DomainScope, List<String>> agentIdsByDomain =
        const <DomainScope, List<String>>{},
  }) : _database = database,
       _ownerUserId = ownerUserId,
       _specs = List<DomainDataManagementSpec>.unmodifiable(specs),
       _agentIdsByDomain = agentIdsByDomain {
    for (final spec in _specs) {
      for (final table in <DataTableSpec>[
        ...spec.sourceTables,
        ...spec.cacheTables,
      ]) {
        _validateTableName(table.table);
      }
    }
  }

  final AppDatabase _database;
  final String _ownerUserId;
  final List<DomainDataManagementSpec> _specs;
  final Map<DomainScope, List<String>> _agentIdsByDomain;

  Future<List<DomainDataSnapshot>> inspectAll() async {
    final snapshots = <DomainDataSnapshot>[];
    for (final spec in _specs) {
      var sourceRows = 0;
      var deletedRows = 0;
      var cacheRows = 0;
      for (final table in spec.sourceTables) {
        sourceRows += await _count(table, deleted: false);
        if (table.hasTombstones) {
          deletedRows += await _count(table, deleted: true);
        }
      }
      for (final table in spec.cacheTables) {
        cacheRows += await _count(table);
      }
      snapshots.add(
        DomainDataSnapshot(
          scope: spec.scope,
          label: spec.label,
          sourceRows: sourceRows,
          deletedRows: deletedRows,
          cacheRows: cacheRows,
          sourceTableCount: spec.sourceTables.length,
          cacheTableCount: spec.cacheTables.length,
        ),
      );
    }
    return snapshots;
  }

  /// Inspects local-only history that is intentionally outside every domain's
  /// synced source tables. Counts are isolated to the signed-in user.
  Future<SharedDataSnapshot> inspectSharedData() async {
    final chatRows =
        await _countOwnerRows('chat_sessions') +
        await _countOwnerRows('chat_messages');
    final aiRows =
        await _countOwnerRows('ai_traces') +
        await _countOwnerRows('ai_undo_stack') +
        await _countOwnerRows('ai_touched_entities');
    final memoryRows =
        await _countOwnerRows('memories') +
        await _countOwnerRows('events') +
        await _countOwnerRows('domain_event_log', ownerColumn: 'actor_user_id');
    final agentRows =
        await _countOwnerRows('agent_runs') +
        await _countOwnerRows('agent_runtime_checkpoints') +
        await _countOwnerRows('agent_artifacts');
    final pageCount = await _pragmaInt('page_count');
    final pageSize = await _pragmaInt('page_size');
    final freePages = await _pragmaInt('freelist_count');
    return SharedDataSnapshot(
      chatRows: chatRows,
      aiRows: aiRows,
      memoryRows: memoryRows,
      agentRows: agentRows,
      databaseBytes: pageCount * pageSize,
      reclaimableBytes: freePages * pageSize,
    );
  }

  /// Removes local AI/chat/memory/agent history without touching domain source
  /// data, sync generations, credentials, or agent preferences.
  Future<int> clearSharedHistory() async {
    var affected = 0;
    await _database.transaction(() async {
      await _database.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final table in const <String>[
        'chat_messages',
        'chat_sessions',
        'ai_undo_stack',
        'ai_touched_entities',
        'ai_traces',
        'agent_runtime_checkpoints',
        'agent_artifacts',
        'agent_runs',
        'memories',
        'events',
      ]) {
        affected += await _deleteWhere(table, 'owner_user_id = ?', <Object?>[
          _ownerUserId,
        ]);
      }
      affected += await _deleteWhere(
        'domain_event_log',
        'actor_user_id = ?',
        <Object?>[_ownerUserId],
      );
    });
    await _database.customStatement('PRAGMA optimize');
    return affected;
  }

  /// Rewrites the SQLite file so free pages created by cleanup are returned to
  /// the filesystem. This is intentionally manual because VACUUM can be slow.
  Future<SharedDataSnapshot> compactDatabase() async {
    await _database.customStatement('VACUUM');
    return inspectSharedData();
  }

  /// Hard-deletes only resources explicitly registered as re-creatable cache.
  Future<int> clearCache(DomainScope scope) async {
    DomainDataManagementSpec? spec;
    for (final candidate in _specs) {
      if (candidate.scope == scope) {
        spec = candidate;
        break;
      }
    }
    if (spec == null || spec.cacheTables.isEmpty) return 0;
    final resolvedSpec = spec;

    var deleted = 0;
    await _database.transaction(() async {
      for (final table in resolvedSpec.cacheTables) {
        final where = table.ownerScoped ? ' WHERE owner_user_id = ?' : '';
        deleted += await _database.customUpdate(
          'DELETE FROM ${table.table}$where',
          variables: table.ownerScoped
              ? <Variable<Object>>[Variable<String>(_ownerUserId)]
              : const <Variable<Object>>[],
        );
      }
    });
    return deleted;
  }

  /// Hard-resets one domain on this device.
  ///
  /// This is also used when sync reports a newer server generation. Shared
  /// Memory/Agent/Audit projections are removed by domain ownership, while
  /// explicitly preserved identity/config rows can be requeued into the new
  /// generation after an all-device reset.
  Future<int> resetLocalDomain(
    DomainScope scope, {
    bool requeuePreserved = false,
  }) async {
    final spec = _specFor(scope);
    if (spec == null) return 0;
    final resetTables = spec.sourceTables
        .where((table) => !table.preserveOnReset)
        .toList(growable: false);
    final preservedTables = spec.sourceTables
        .where((table) => table.preserveOnReset)
        .toList(growable: false);
    final sourceNames = spec.sourceTables
        .map((table) => table.table)
        .toList(growable: false);
    final agentIds = _agentIdsByDomain[scope] ?? const <String>[];
    var affected = 0;

    await _database.transaction(() async {
      await _database.customStatement('PRAGMA defer_foreign_keys = ON');
      affected += await _deleteIn(
        table: 'memories',
        column: 'source',
        values: sourceNames,
        ownerColumn: 'owner_user_id',
      );
      affected += await _deleteIn(
        table: 'events',
        column: 'source',
        values: sourceNames,
        ownerColumn: 'owner_user_id',
      );
      affected += await _deleteIn(
        table: 'domain_event_log',
        column: 'entity_table',
        values: sourceNames,
        ownerColumn: 'actor_user_id',
      );
      affected += await _deleteIn(
        table: 'ai_touched_entities',
        column: 'entity_type',
        values: sourceNames,
        ownerColumn: 'owner_user_id',
      );
      affected += await _deleteWhere(
        'agent_artifacts',
        'owner_user_id = ? AND domain = ?',
        <Object?>[_ownerUserId, scope.wire],
      );
      if (agentIds.isNotEmpty) {
        affected += await _deleteIn(
          table: 'agent_runs',
          column: 'agent_id',
          values: agentIds,
          ownerColumn: 'owner_user_id',
        );
        affected += await _deleteIn(
          table: 'agent_runtime_checkpoints',
          column: 'agent_id',
          values: agentIds,
          ownerColumn: 'owner_user_id',
        );
        affected += await _deleteIn(
          table: 'agent_preferences',
          column: 'agent_id',
          values: agentIds,
          ownerColumn: 'owner_user_id',
        );
      }
      for (final table in spec.cacheTables) {
        affected += await _deleteTableRows(table);
      }
      for (final table in resetTables.reversed) {
        affected += await _deleteTableRows(table);
      }
      affected += await _deleteIn(
        table: 'op_outbox',
        column: 'table_name',
        values: resetTables.map((table) => table.table).toList(),
      );
      if (requeuePreserved) {
        for (final table in preservedTables) {
          await _enqueueTableRows(table);
        }
      }
    });
    return affected;
  }

  DomainDataManagementSpec? _specFor(DomainScope scope) {
    for (final candidate in _specs) {
      if (candidate.scope == scope) return candidate;
    }
    return null;
  }

  Future<int> _deleteTableRows(DataTableSpec table) {
    if (table.ownerScoped) {
      return _deleteWhere(table.table, 'owner_user_id = ?', <Object?>[
        _ownerUserId,
      ]);
    }
    return _database.customUpdate('DELETE FROM ${table.table}');
  }

  Future<int> _deleteWhere(String table, String where, List<Object?> values) {
    _validateTableName(table);
    return _database.customUpdate(
      'DELETE FROM $table WHERE $where',
      variables: values.map(Variable<Object>.new).toList(growable: false),
    );
  }

  Future<int> _deleteIn({
    required String table,
    required String column,
    required List<String> values,
    String? ownerColumn,
  }) async {
    if (values.isEmpty) return 0;
    _validateTableName(table);
    _validateTableName(column);
    if (ownerColumn != null) _validateTableName(ownerColumn);
    final placeholders = List<String>.filled(values.length, '?').join(',');
    final ownerClause = ownerColumn == null ? '' : '$ownerColumn = ? AND ';
    return _database.customUpdate(
      'DELETE FROM $table WHERE $ownerClause$column IN ($placeholders)',
      variables: <Variable<Object>>[
        if (ownerColumn != null) Variable<Object>(_ownerUserId),
        for (final value in values) Variable<Object>(value),
      ],
    );
  }

  Future<int> _enqueueTableRows(DataTableSpec table) async {
    final primaryKey = syncPrimaryKeyForTable(table.table);
    final ownerWhere = table.ownerScoped ? ' WHERE owner_user_id = ?' : '';
    final rows = await _database
        .customSelect(
          'SELECT $primaryKey AS row_id FROM ${table.table}$ownerWhere',
          variables: table.ownerScoped
              ? <Variable<Object>>[Variable<Object>(_ownerUserId)]
              : const <Variable<Object>>[],
        )
        .get();
    for (final row in rows) {
      await _database.customStatement(
        'INSERT INTO op_outbox(op_id, table_name, row_id, created_at) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[
          const Uuid().v4(),
          table.table,
          row.data['row_id'].toString(),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    }
    return rows.length;
  }

  Future<int> _count(DataTableSpec table, {bool? deleted}) async {
    final clauses = <String>[];
    final variables = <Variable<Object>>[];
    if (table.ownerScoped) {
      clauses.add('owner_user_id = ?');
      variables.add(Variable<String>(_ownerUserId));
    }
    if (deleted != null && table.hasTombstones) {
      clauses.add('deleted_at IS ${deleted ? 'NOT ' : ''}NULL');
    }
    final where = clauses.isEmpty ? '' : ' WHERE ${clauses.join(' AND ')}';
    final row = await _database
        .customSelect(
          'SELECT COUNT(*) AS c FROM ${table.table}$where',
          variables: variables,
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<int> _countOwnerRows(
    String table, {
    String ownerColumn = 'owner_user_id',
  }) async {
    _validateTableName(table);
    _validateTableName(ownerColumn);
    final row = await _database
        .customSelect(
          'SELECT COUNT(*) AS c FROM $table WHERE $ownerColumn = ?',
          variables: <Variable<Object>>[Variable<Object>(_ownerUserId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<int> _pragmaInt(String name) async {
    _validateTableName(name);
    final row = await _database.customSelect('PRAGMA $name').getSingle();
    return row.data.values.single as int;
  }

  static void _validateTableName(String table) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(table)) {
      throw ArgumentError.value(table, 'table', 'Invalid registered table');
    }
  }
}
