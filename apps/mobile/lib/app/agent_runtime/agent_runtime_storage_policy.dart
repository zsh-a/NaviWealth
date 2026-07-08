/// Storage ownership policy for the app-level FRB agent-runtime adapters.
///
/// NaviWealth keeps product-visible AI persistence in the Flutter-owned Drift
/// database: traces, agent runs, artifacts, undo state, and touched entities.
/// The upstream runtime's SQLite store is a Rust implementation detail and is
/// not a stable product schema for Flutter UI or repositories.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

final agentRuntimeStoragePolicyProvider = Provider<AgentRuntimeStoragePolicy>(
  (ref) => const AgentRuntimeStoragePolicy.appOwned(),
);

enum AgentRuntimeStorageMode { appOwned, runtimeOwnedSqliteDebug }

class AgentRuntimeStoragePolicy {
  const AgentRuntimeStoragePolicy.appOwned()
    : mode = AgentRuntimeStorageMode.appOwned,
      storePath = null;

  const AgentRuntimeStoragePolicy.runtimeOwnedSqliteDebug({
    required String this.storePath,
  }) : mode = AgentRuntimeStorageMode.runtimeOwnedSqliteDebug;

  final AgentRuntimeStorageMode mode;
  final String? storePath;

  bool get isAppOwned => mode == AgentRuntimeStorageMode.appOwned;

  void requireAppOwned({required String surface}) {
    if (isAppOwned) return;
    throw UnsupportedError(
      '$surface only supports app-owned Drift persistence. '
      'Runtime-owned SQLite is reserved for future debug/replay bridge APIs '
      'and must not be used as NaviWealth product storage.',
    );
  }
}
