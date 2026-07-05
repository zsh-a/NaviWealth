/// Riverpod wiring for the cross-domain agent framework.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../persistence/providers.dart';
import 'agent_artifact_store.dart';
import 'agent_preference_store.dart';
import 'agent_run_store.dart';

final agentPreferenceRevisionProvider = StateProvider<int>((ref) => 0);

final agentRunStoreProvider = FutureProvider<AgentRunStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SqliteAgentRunStore(db: db);
});

final agentPreferenceStoreProvider = FutureProvider<AgentPreferenceStore>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SqliteAgentPreferenceStore(db: db);
});

final agentArtifactStoreProvider = FutureProvider<AgentArtifactStore>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SqliteAgentArtifactStore(db: db);
});
