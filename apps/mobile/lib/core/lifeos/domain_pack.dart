/// LifeOS cross-domain registration seam (`docs/lifeos-shell.md` §4).
///
/// Each LifeOS domain (Finance / Health / Knowledge / future) declares
/// itself once as a [DomainPack] and registers into
/// [domainPackRegistryProvider]. The four shell aggregators that used
/// to repeat the same opt-in branching (device tools, system-prompt
/// blocks, shell specs, agent list) all read [activeDomainPacksProvider]
/// instead — adding a new domain is now a single entry in the registry,
/// not a four-site edit in `bootstrap.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/agents/agent.dart';
import '../ai/runtime/device/tools/device_tool.dart';
import '../auth/domain_scope.dart';
import '../auth/providers.dart';
import '../shell/domain_shell.dart';

/// Builds the per-turn list of [Agent]s a domain contributes. Receives
/// [Ref] because most agents are themselves Riverpod-built (they depend
/// on runtime services like the LLM client or notification service).
typedef DomainAgentBuilder = List<Agent> Function(Ref ref);

/// Static description of one LifeOS domain's shell contributions. Held
/// as a `const` value next to the domain's tool barrel, so the inventory
/// list in `lib/app/domain_packs.dart` is the single grep-able answer to
/// "what domains does this build have?".
class DomainPack {
  const DomainPack({
    required this.scope,
    this.deviceTools = const <DeviceTool>[],
    this.systemPromptBlock = '',
    this.shellSpecBuilder,
    this.agentBuilder,
  });

  /// Opt-in scope this pack registers under.
  final DomainScope scope;

  /// Device AI tools advertised when this domain is active.
  final List<DeviceTool> deviceTools;

  /// System-prompt block appended onto [kDeviceSystemPromptBase].
  /// Empty string = no prompt contribution.
  final String systemPromptBlock;

  /// Localised shell spec (4-tab IA, color, dock placement). Null when
  /// the domain has no top-level shell presence yet.
  final DomainShellSpecBuilder? shellSpecBuilder;

  /// Builds the per-turn list of [Agent]s. Null when the domain has no
  /// agents (e.g. FinanceOS today). Non-null builders typically read
  /// one or more agent providers from `ref` so each agent stays
  /// composition-blind.
  final DomainAgentBuilder? agentBuilder;
}

/// Inventory of all known [DomainPack]s. Default empty; `bootstrap.dart`
/// overrides this with the production list (`kAllDomainPacks`). Tests
/// can override with a subset to exercise shell behaviour with a
/// reduced domain matrix.
final domainPackRegistryProvider = Provider<List<DomainPack>>(
  (ref) => const <DomainPack>[],
);

/// Packs whose `scope` is in the user's opt-in set. The four shell
/// aggregators (device tools, system-prompt blocks, agents, domain
/// shells) all derive from this so the active-domain calculation lives
/// in exactly one place. Finance is always present — [DomainOptIns]
/// guarantees it in its constructor.
final activeDomainPacksProvider = Provider<List<DomainPack>>((ref) {
  final all = ref.watch(domainPackRegistryProvider);
  final optIns =
      ref.watch(domainOptInsProvider).value ?? DomainOptIns.financeOnly;
  return [for (final p in all) if (optIns.contains(p.scope)) p];
});
