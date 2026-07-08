/// Riverpod wiring for the cross-domain agent framework.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../auth/current_user.dart';
import '../../auth/domain_scope.dart';
import '../../persistence/providers.dart';
import 'agent_artifact.dart';
import 'agent_artifact_store.dart';
import 'agent_preference_store.dart';
import 'agent_presentation.dart';
import 'agent_registry.dart';
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

class AgentResultScope {
  const AgentResultScope({
    required this.domain,
    required this.placement,
    this.limit = 5,
  });

  final DomainScope domain;
  final AgentResultPlacement placement;
  final int limit;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentResultScope &&
            other.domain == domain &&
            other.placement == placement &&
            other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(domain, placement, limit);
}

class AgentResultBundle {
  const AgentResultBundle({required this.artifacts, required this.latestRuns});

  static const empty = AgentResultBundle(
    artifacts: <AgentArtifact>[],
    latestRuns: <AgentRunRecord>[],
  );

  final List<AgentArtifact> artifacts;
  final List<AgentRunRecord> latestRuns;

  AgentRunRecord? get latestRun => latestRuns.isEmpty ? null : latestRuns.first;
}

final latestAgentResultsForPlacementProvider = FutureProvider.autoDispose
    .family<AgentResultBundle, AgentResultScope>((ref, scope) async {
      if (scope.limit <= 0) return AgentResultBundle.empty;
      final registrations = ref.watch(agentRegistrationProvider);
      final presentations = ref.watch(agentPresentationSpecsProvider);
      final agentIds = <String>[
        for (final registration in registrations)
          if (registration.domain == scope.domain &&
              presentations[registration.agent.id]?.placement ==
                  scope.placement)
            registration.agent.id,
      ];
      if (agentIds.isEmpty) return AgentResultBundle.empty;

      final ownerUserId = await ref.read(currentUserIdProvider)();
      final artifactStore = await ref.watch(agentArtifactStoreProvider.future);
      final runStore = await ref.watch(agentRunStoreProvider.future);
      final artifactsByAgent = await artifactStore.latestForAgents(
        ownerUserId: ownerUserId,
        agentIds: agentIds,
      );
      final runsByAgent = await runStore.latestForAgents(
        ownerUserId: ownerUserId,
        agentIds: agentIds,
      );
      final artifacts = artifactsByAgent.values.toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final runs = runsByAgent.values.toList(growable: false)
        ..sort((a, b) => _runReferenceTime(b).compareTo(_runReferenceTime(a)));
      return AgentResultBundle(
        artifacts: artifacts.take(scope.limit).toList(growable: false),
        latestRuns: runs.take(scope.limit).toList(growable: false),
      );
    });

DateTime _runReferenceTime(AgentRunRecord record) {
  return record.finishedAt ?? record.startedAt;
}
