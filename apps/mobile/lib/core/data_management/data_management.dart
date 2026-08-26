import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../auth/domain_scope.dart';
import '../logging/app_logger.dart';
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
    AppLogger? logger,
  }) : _database = database,
       _ownerUserId = ownerUserId,
       _specs = List<DomainDataManagementSpec>.unmodifiable(specs),
       _agentIdsByDomain = agentIdsByDomain,
       _logger = logger ?? AppLogger.instance {
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
  final AppLogger _logger;

  /// Normalizes values returned by SQLite PRAGMA statements.
  ///
  /// SQLite drivers do not expose PRAGMA integer results consistently: the
  /// native driver usually returns an [int], while some platform/web drivers
  /// return a numeric [String]. Keep the conversion at this boundary so the
  /// storage page does not depend on a driver's runtime representation.
  @visibleForTesting
  static int parsePragmaIntValue(Object? value, {required String pragma}) {
    if (value is int) return value;
    if (value is num) {
      if (!value.isFinite) {
        throw StateError(
          'PRAGMA $pragma returned a non-finite numeric value '
          '(type=${value.runtimeType})',
        );
      }
      final integer = value.toInt();
      if (value == integer) return integer;
    } else if (value is String) {
      final parsed = num.tryParse(value.trim());
      if (parsed != null && parsed.isFinite) {
        final integer = parsed.toInt();
        if (parsed == integer) return integer;
      }
    }
    throw StateError(
      'PRAGMA $pragma returned a non-integer value '
      '(type=${value.runtimeType})',
    );
  }

  Future<List<DomainDataSnapshot>> inspectAll() async {
    try {
      final snapshots = <DomainDataSnapshot>[];
      for (final spec in _specs) {
        var sourceRows = 0;
        var deletedRows = 0;
        var cacheRows = 0;
        for (final table in spec.sourceTables) {
          sourceRows += await _count(
            table,
            deleted: false,
            domain: spec.scope.wire,
            stage: 'source_rows',
          );
          if (table.hasTombstones) {
            deletedRows += await _count(
              table,
              deleted: true,
              domain: spec.scope.wire,
              stage: 'deleted_rows',
            );
          }
        }
        for (final table in spec.cacheTables) {
          cacheRows += await _count(
            table,
            domain: spec.scope.wire,
            stage: 'cache_rows',
          );
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
    } catch (error, stackTrace) {
      _logger.e(
        'data_management.inspect_domains failed stage=inspect_tables '
        'domain_count=${_specs.length}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Inspects local-only history that is intentionally outside every domain's
  /// synced source tables. Counts are isolated to the signed-in user.
  Future<SharedDataSnapshot> inspectSharedData() async {
    try {
      final chatRows =
          await _countOwnerRows('chat_sessions', resource: 'chat') +
          await _countOwnerRows('chat_messages', resource: 'chat') +
          await _countOwnerRows('conversation_checkpoints', resource: 'chat');
      final aiRows =
          await _countOwnerRows('ai_traces', resource: 'ai') +
          await _countOwnerRows('ai_undo_stack', resource: 'ai') +
          await _countOwnerRows('ai_touched_entities', resource: 'ai');
      final memoryRows =
          await _countOwnerRows('memories', resource: 'memory') +
          await _countOwnerRows('memory_candidates', resource: 'memory') +
          await _countOwnerRows('events', resource: 'memory') +
          await _countOwnerRows(
            'domain_event_log',
            ownerColumn: 'actor_user_id',
            resource: 'memory',
          );
      final agentRows =
          await _countOwnerRows('agent_runs', resource: 'agent') +
          await _countOwnerRows(
            'agent_runtime_checkpoints',
            resource: 'agent',
          ) +
          await _countOwnerRows('agent_artifacts', resource: 'agent') +
          await _countOwnerRows('agent_findings', resource: 'agent');
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
    } catch (error, stackTrace) {
      _logger.e(
        'data_management.inspect_shared failed stage=inspect_shared_tables',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Removes local AI/chat/memory/agent history without touching domain source
  /// data, sync generations, credentials, or agent preferences.
  Future<int> clearSharedHistory() async {
    var affected = 0;
    await _database.transaction(() async {
      await _database.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final table in const <String>[
        'conversation_checkpoints',
        'chat_messages',
        'chat_sessions',
        'ai_undo_stack',
        'ai_touched_entities',
        'ai_traces',
        'agent_runtime_checkpoints',
        'agent_artifacts',
        'agent_findings',
        'agent_runs',
        'memory_candidates',
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
      affected += await _deleteWhere(
        'personal_profile_facts',
        'owner_user_id = ? AND domain_scope = ?',
        <Object?>[_ownerUserId, scope.wire],
      );
      affected += await _deleteWhere(
        'events',
        'owner_user_id = ? AND domain = ?',
        <Object?>[_ownerUserId, scope.wire],
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
      affected += await _deleteWhere(
        'agent_findings',
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

  Future<int> _count(
    DataTableSpec table, {
    bool? deleted,
    required String domain,
    required String stage,
  }) async {
    try {
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
    } catch (error, stackTrace) {
      _logTableFailure(
        operation: 'inspect_domains',
        stage: stage,
        domain: domain,
        table: table.table,
        ownerScoped: table.ownerScoped,
        deleted: deleted,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<int> _countOwnerRows(
    String table, {
    String ownerColumn = 'owner_user_id',
    required String resource,
  }) async {
    try {
      _validateTableName(table);
      _validateTableName(ownerColumn);
      final row = await _database
          .customSelect(
            'SELECT COUNT(*) AS c FROM $table WHERE $ownerColumn = ?',
            variables: <Variable<Object>>[Variable<Object>(_ownerUserId)],
          )
          .getSingle();
      return row.read<int>('c');
    } catch (error, stackTrace) {
      _logTableFailure(
        operation: 'inspect_shared',
        stage: 'count_${resource}_rows',
        domain: 'shared',
        table: table,
        ownerScoped: true,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<int> _pragmaInt(String name) async {
    try {
      _validateTableName(name);
      final row = await _database.customSelect('PRAGMA $name').getSingle();
      return parsePragmaIntValue(row.data.values.single, pragma: name);
    } catch (error, stackTrace) {
      _logger.e(
        'data_management.inspect_shared failed stage=read_pragma pragma=$name',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _logTableFailure({
    required String operation,
    required String stage,
    required String domain,
    required String table,
    required bool ownerScoped,
    bool? deleted,
    required Object error,
    required StackTrace stackTrace,
  }) {
    _logger.e(
      'data_management.$operation failed '
      'stage=$stage domain=$domain table=$table '
      'owner_scoped=$ownerScoped '
      'deleted_filter=${deleted?.toString() ?? 'none'}',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void _validateTableName(String table) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(table)) {
      throw ArgumentError.value(table, 'table', 'Invalid registered table');
    }
  }
}
