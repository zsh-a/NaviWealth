/// Cross-domain agent registry (`docs/architecture/lifeos-shell.md` §7.3, D-2.5).
///
/// Each domain registers its agents through this seam. `bootstrap.dart`
/// overrides the provider with the union of every domain's agents,
/// gated by `domainOptInsProvider` so a disabled domain contributes
/// nothing.
///
/// Default: empty — a shell-only build has no agents and the runner's
/// tick is a no-op.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lifeos/domain_pack.dart';
import 'agent.dart';

final agentRegistrationProvider = Provider<List<DomainAgentRegistration>>(
  (ref) => const <DomainAgentRegistration>[],
);

/// App-owned orchestration agents that do not belong to an opt-in domain.
final appAgentRegistryProvider = Provider<List<Agent>>(
  (ref) => const <Agent>[],
);

final agentRegistryProvider = Provider<List<Agent>>((ref) {
  return [
    ...ref.watch(appAgentRegistryProvider),
    for (final registration in ref.watch(agentRegistrationProvider))
      registration.agent,
  ];
});
