/// Local user preferences for LifeOS agents.
///
/// Preferences are device-local product state. They control scheduling and
/// notifications, but they do not change the agent registry itself.
library;

import 'package:drift/drift.dart';

import '../../persistence/app_database.dart';

class AgentPreference {
  const AgentPreference({
    required this.ownerUserId,
    required this.agentId,
    required this.enabled,
    required this.notificationsEnabled,
    required this.updatedAt,
  });

  final String ownerUserId;
  final String agentId;
  final bool enabled;
  final bool notificationsEnabled;
  final DateTime updatedAt;
}

abstract interface class AgentPreferenceStore {
  Future<AgentPreference> preferenceFor({
    required String ownerUserId,
    required String agentId,
  });

  Future<bool> isEnabled({
    required String ownerUserId,
    required String agentId,
  });

  Future<void> setEnabled({
    required String ownerUserId,
    required String agentId,
    required bool enabled,
    required DateTime updatedAt,
  });

  Future<void> setNotificationsEnabled({
    required String ownerUserId,
    required String agentId,
    required bool enabled,
    required DateTime updatedAt,
  });

  Future<List<AgentPreference>> listForOwner({required String ownerUserId});
}

class InMemoryAgentPreferenceStore implements AgentPreferenceStore {
  final Map<String, AgentPreference> _preferences = <String, AgentPreference>{};

  @override
  Future<AgentPreference> preferenceFor({
    required String ownerUserId,
    required String agentId,
  }) async {
    return _preferences[_key(ownerUserId, agentId)] ??
        AgentPreference(
          ownerUserId: ownerUserId,
          agentId: agentId,
          enabled: true,
          notificationsEnabled: true,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
  }

  @override
  Future<bool> isEnabled({
    required String ownerUserId,
    required String agentId,
  }) async {
    final pref = await preferenceFor(
      ownerUserId: ownerUserId,
      agentId: agentId,
    );
    return pref.enabled;
  }

  @override
  Future<void> setEnabled({
    required String ownerUserId,
    required String agentId,
    required bool enabled,
    required DateTime updatedAt,
  }) async {
    final current = await preferenceFor(
      ownerUserId: ownerUserId,
      agentId: agentId,
    );
    _preferences[_key(ownerUserId, agentId)] = AgentPreference(
      ownerUserId: ownerUserId,
      agentId: agentId,
      enabled: enabled,
      notificationsEnabled: current.notificationsEnabled,
      updatedAt: updatedAt.toUtc(),
    );
  }

  @override
  Future<void> setNotificationsEnabled({
    required String ownerUserId,
    required String agentId,
    required bool enabled,
    required DateTime updatedAt,
  }) async {
    final current = await preferenceFor(
      ownerUserId: ownerUserId,
      agentId: agentId,
    );
    _preferences[_key(ownerUserId, agentId)] = AgentPreference(
      ownerUserId: ownerUserId,
      agentId: agentId,
      enabled: current.enabled,
      notificationsEnabled: enabled,
      updatedAt: updatedAt.toUtc(),
    );
  }

  @override
  Future<List<AgentPreference>> listForOwner({
    required String ownerUserId,
  }) async {
    final rows =
        _preferences.values
            .where((pref) => pref.ownerUserId == ownerUserId)
            .toList()
          ..sort((a, b) => a.agentId.compareTo(b.agentId));
    return rows;
  }
}

class SqliteAgentPreferenceStore implements AgentPreferenceStore {
  SqliteAgentPreferenceStore({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<AgentPreference> preferenceFor({
    required String ownerUserId,
    required String agentId,
  }) async {
    final row = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_preferences
          WHERE owner_user_id = ? AND agent_id = ?
          ''',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(agentId),
          ],
        )
        .getSingleOrNull();
    return row == null
        ? AgentPreference(
            ownerUserId: ownerUserId,
            agentId: agentId,
            enabled: true,
            notificationsEnabled: true,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          )
        : _rowToPreference(row);
  }

  @override
  Future<bool> isEnabled({
    required String ownerUserId,
    required String agentId,
  }) async {
    final pref = await preferenceFor(
      ownerUserId: ownerUserId,
      agentId: agentId,
    );
    return pref.enabled;
  }

  @override
  Future<void> setEnabled({
    required String ownerUserId,
    required String agentId,
    required bool enabled,
    required DateTime updatedAt,
  }) async {
    await _db.customStatement(
      '''
      INSERT INTO agent_preferences (
        owner_user_id,
        agent_id,
        enabled,
        notifications_enabled,
        updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(owner_user_id, agent_id) DO UPDATE SET
        enabled = excluded.enabled,
        updated_at = excluded.updated_at
      ''',
      <Object?>[
        ownerUserId,
        agentId,
        enabled ? 1 : 0,
        1,
        updatedAt.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> setNotificationsEnabled({
    required String ownerUserId,
    required String agentId,
    required bool enabled,
    required DateTime updatedAt,
  }) async {
    final current = await preferenceFor(
      ownerUserId: ownerUserId,
      agentId: agentId,
    );
    await _db.customStatement(
      '''
      INSERT INTO agent_preferences (
        owner_user_id,
        agent_id,
        enabled,
        notifications_enabled,
        updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(owner_user_id, agent_id) DO UPDATE SET
        notifications_enabled = excluded.notifications_enabled,
        updated_at = excluded.updated_at
      ''',
      <Object?>[
        ownerUserId,
        agentId,
        current.enabled ? 1 : 0,
        enabled ? 1 : 0,
        updatedAt.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<List<AgentPreference>> listForOwner({
    required String ownerUserId,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT *
          FROM agent_preferences
          WHERE owner_user_id = ?
          ORDER BY agent_id ASC
          ''',
          variables: [Variable.withString(ownerUserId)],
        )
        .get();
    return [for (final row in rows) _rowToPreference(row)];
  }
}

String _key(String ownerUserId, String agentId) => '$ownerUserId::$agentId';

AgentPreference _rowToPreference(QueryRow row) {
  return AgentPreference(
    ownerUserId: row.read<String>('owner_user_id'),
    agentId: row.read<String>('agent_id'),
    enabled: row.read<int>('enabled') != 0,
    notificationsEnabled: row.read<int>('notifications_enabled') != 0,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('updated_at'),
      isUtc: true,
    ),
  );
}
