import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/current_user.dart';
import '../../persistence/app_database.dart';
import '../../persistence/providers.dart';
import 'scheduled_agent_task.dart';

class ScheduledAgentStore {
  const ScheduledAgentStore(this.db, this.ownerUserId);
  final AppDatabase db;
  final String ownerUserId;

  Future<List<ScheduledAgentTask>> list() async {
    final rows = await db
        .customSelect(
          'SELECT definition_json FROM scheduled_agent_tasks WHERE owner_user_id = ?',
          variables: [Variable.withString(ownerUserId)],
        )
        .get();
    return rows
        .map(
          (row) => ScheduledAgentTask.fromJson(
            jsonDecode(row.read<String>('definition_json'))
                as Map<String, Object?>,
          ),
        )
        .toList();
  }

  Future<void> save(
    ScheduledAgentTask task, {
    required int expectedRevision,
  }) async {
    await db.transaction(() async {
      final rows = await list();
      final existing = rows.where((row) => row.id == task.id).firstOrNull;
      if ((existing?.revision ?? 0) != expectedRevision ||
          task.revision != expectedRevision + 1) {
        throw StateError('Task changed; reload before saving');
      }
      await db.customStatement(
        'INSERT INTO scheduled_agent_tasks(owner_user_id, id, definition_json) VALUES (?, ?, ?) '
        'ON CONFLICT(owner_user_id, id) DO UPDATE SET definition_json = excluded.definition_json',
        [ownerUserId, task.id, jsonEncode(task.toJson())],
      );
    });
  }
}

final scheduledAgentStoreProvider = FutureProvider<ScheduledAgentStore>(
  (ref) async => ScheduledAgentStore(
    await ref.watch(appDatabaseProvider.future),
    await ref.watch(currentUserIdProvider)(),
  ),
);

final scheduledAgentTasksProvider = FutureProvider<List<ScheduledAgentTask>>(
  (ref) async => (await (await ref.watch(
    scheduledAgentStoreProvider.future,
  )).list()).where((task) => !task.archived).toList(),
);
