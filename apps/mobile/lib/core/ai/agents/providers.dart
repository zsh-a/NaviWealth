/// Riverpod wiring for the cross-domain agent framework.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../persistence/providers.dart';
import 'agent_artifact_store.dart';

final agentArtifactStoreProvider = FutureProvider<AgentArtifactStore>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SqliteAgentArtifactStore(db: db);
});
