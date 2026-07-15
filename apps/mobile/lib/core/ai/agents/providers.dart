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

  /// One result lane per agent. Artifacts and run state are paired by
  /// [AgentResultEntry.agentId] before presentation so a run can never decorate another
  /// agent's result.
  List<AgentResultEntry> get entries {
    final artifactsByAgent = <String, AgentArtifact>{
      for (final artifact in artifacts) artifact.agentId: artifact,
    };
    final runsByAgent = <String, AgentRunRecord>{
      for (final run in latestRuns) run.agentId: run,
    };
    final agentIds = <String>{...artifactsByAgent.keys, ...runsByAgent.keys};
    final values = <AgentResultEntry>[
      for (final agentId in agentIds)
        AgentResultEntry(
          agentId: agentId,
          artifact: artifactsByAgent[agentId],
          run: runsByAgent[agentId],
        ),
    ]..sort(_compareAgentResultEntries);
    return values;
  }

  List<AgentResultEntry> get visibleEntries => entries
      .where(
        (entry) =>
            entry.artifact != null ||
            entry.run?.status == AgentRunLifecycleStatus.running ||
            entry.run?.status == AgentRunLifecycleStatus.failed,
      )
      .toList(growable: false);

  AgentArtifact? get latestArtifact =>
      artifacts.isEmpty ? null : artifacts.first;

  AgentRunRecord? get latestRun => latestRuns.isEmpty ? null : latestRuns.first;

  /// When true, domain UIs should *overlay* run status on the latest
  /// artifact — never replace readable result body with a status-only card.
  ///
  /// Prefer [AgentResultSurface] which implements this policy.
  AgentRunRecord? get runOverlay {
    final run = latestRun;
    if (run == null || !shouldPrioritizeRun(run, latestArtifact)) {
      return null;
    }
    return run;
  }

  /// Legacy name — same as [runOverlay]. Prefer [runOverlay].
  AgentRunRecord? get runToShowBeforeArtifacts => runOverlay;

  /// Whether [run] is a live interrupt (running / failed) relative to [artifact].
  /// Used as an overlay signal, not as permission to hide the artifact.
  static bool shouldPrioritizeRun(AgentRunRecord run, AgentArtifact? artifact) {
    if (!_runCanInterruptArtifacts(run.status)) return false;
    if (artifact == null) return true;
    if (run.agentId != artifact.agentId) return false;
    return _runReferenceTime(run).isAfter(artifact.createdAt);
  }
}

class AgentResultEntry {
  const AgentResultEntry({required this.agentId, this.artifact, this.run});

  final String agentId;
  final AgentArtifact? artifact;
  final AgentRunRecord? run;

  AgentRunRecord? get runOverlay {
    final value = run;
    return value != null &&
            AgentResultBundle.shouldPrioritizeRun(value, artifact)
        ? value
        : null;
  }

  DateTime get referenceTime {
    final artifactTime = artifact?.createdAt;
    final value = run;
    final runTime = value == null ? null : _runReferenceTime(value);
    if (artifactTime == null) return runTime!;
    if (runOverlay == null) return artifactTime;
    if (runTime == null || artifactTime.isAfter(runTime)) return artifactTime;
    return runTime;
  }
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

bool _runCanInterruptArtifacts(AgentRunLifecycleStatus status) {
  return status == AgentRunLifecycleStatus.running ||
      status == AgentRunLifecycleStatus.failed;
}

int _compareAgentResultEntries(AgentResultEntry a, AgentResultEntry b) {
  final byPriority = _entryPriority(b).compareTo(_entryPriority(a));
  if (byPriority != 0) return byPriority;
  return b.referenceTime.compareTo(a.referenceTime);
}

int _entryPriority(AgentResultEntry entry) {
  final run = entry.runOverlay;
  if (run?.status == AgentRunLifecycleStatus.failed) return 40;
  final severity = entry.artifact?.severity;
  if (severity != null) return _severityRank(severity) * 10;
  if (run?.status == AgentRunLifecycleStatus.running) return 5;
  return 0;
}

int _severityRank(AgentArtifactSeverity severity) => switch (severity) {
  AgentArtifactSeverity.warning => 3,
  AgentArtifactSeverity.attention => 2,
  AgentArtifactSeverity.info => 1,
};
