/// Active-user access guard for opening persisted agent artifacts.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/current_user.dart';
import '../../auth/domain_scope.dart';
import '../../auth/providers.dart' as auth;
import 'agent.dart';
import 'agent_artifact.dart';
import 'agent_artifact_store.dart';
import 'agent_registry.dart';
import 'providers.dart';

Future<AgentArtifact?> readActiveAgentArtifact(
  Ref ref, {
  required String artifactId,
  String? expectedDomain,
}) {
  return _readActiveAgentArtifact(
    artifactId: artifactId,
    expectedDomain: expectedDomain,
    readStore: () => ref.read(agentArtifactStoreProvider.future),
    readOwnerUserId: () => ref.read(currentUserIdProvider)(),
    readOptIns: () => ref.read(auth.domainOptInsProvider.future),
    readAgents: () => ref.read(agentRegistryProvider),
  );
}

Future<AgentArtifact?> readActiveAgentArtifactFromWidgetRef(
  WidgetRef ref, {
  required String artifactId,
  String? expectedDomain,
}) {
  return _readActiveAgentArtifact(
    artifactId: artifactId,
    expectedDomain: expectedDomain,
    readStore: () => ref.read(agentArtifactStoreProvider.future),
    readOwnerUserId: () => ref.read(currentUserIdProvider)(),
    readOptIns: () => ref.read(auth.domainOptInsProvider.future),
    readAgents: () => ref.read(agentRegistryProvider),
  );
}

Future<AgentArtifact?> _readActiveAgentArtifact({
  required String artifactId,
  String? expectedDomain,
  required Future<AgentArtifactStore> Function() readStore,
  required Future<String> Function() readOwnerUserId,
  required Future<DomainOptIns> Function() readOptIns,
  required List<Agent> Function() readAgents,
}) async {
  final id = artifactId.trim();
  if (id.isEmpty) return null;

  final store = await readStore();
  final artifact = await store.read(id);
  if (artifact == null) return null;

  final ownerUserId = await readOwnerUserId();
  if (artifact.ownerUserId != ownerUserId) return null;

  if (expectedDomain != null && artifact.domain != expectedDomain) {
    return null;
  }

  final scope = DomainScope.tryParse(artifact.domain);
  if (scope == null) return null;
  final optIns = await readOptIns();
  if (!optIns.contains(scope)) return null;

  final activeAgentIds = {for (final agent in readAgents()) agent.id};
  if (!activeAgentIds.contains(artifact.agentId)) return null;

  return artifact;
}
