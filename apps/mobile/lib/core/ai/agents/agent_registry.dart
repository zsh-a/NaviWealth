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

import 'agent.dart';

final agentRegistryProvider = Provider<List<Agent>>(
  (ref) => const <Agent>[],
);
