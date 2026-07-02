/// LifeOS cross-domain registration seam (`docs/architecture/lifeos-shell.md` §4).
///
/// Each LifeOS domain (Finance / Health / Knowledge / future) declares
/// itself once as a [DomainPack] and registers into
/// [domainPackRegistryProvider]. The four shell aggregators that used
/// to repeat the same opt-in branching (device tools, system-prompt
/// blocks, proposal kinds, proposal applier routes, shell specs, agent list,
/// memory indexers, background jobs) all read this registry seam instead —
/// adding a new domain is now a single entry in the registry, not scattered
/// edits in `bootstrap.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../ai/agents/agent.dart';
import '../ai/composition/composite_proposal_applier.dart';
import '../ai/composition/proposal_kind_registry.dart';
import '../ai/contracts/tool_descriptor.dart';
import '../ai/intent/intent_policy.dart';
import '../ai/runtime/device/tools/device_tool.dart';
import '../auth/domain_scope.dart';
import '../auth/providers.dart';
import '../command_palette/command_palette_entry.dart';
import '../shell/domain_shell.dart';

/// Builds the per-turn list of [Agent]s a domain contributes. Receives
/// [Ref] because most agents are themselves Riverpod-built (they depend
/// on runtime services like the LLM client or notification service).
typedef DomainAgentBuilder = List<Agent> Function(Ref ref);

/// Agent plus the domain that registered it. Runtime metadata exporters use
/// this instead of guessing ownership from agent ids.
class DomainAgentRegistration {
  const DomainAgentRegistration({required this.agent, required this.domain});

  final Agent agent;
  final DomainScope domain;
}

/// Returns the top-level [StatefulShellRoute] the domain mounts under
/// the dock shell. Called once during router construction.
typedef DomainShellRouteBuilder = StatefulShellRoute Function();

/// Eagerly resolves every `deferred as` library reachable from this
/// domain's routes — see `preloadFinanceDeferredRoutesForTest`. Domains
/// that ship every page in the main bundle leave this `null`.
typedef DomainDeferredPreloader = Future<void> Function();

/// Builds the domain's contributions to the shared Cmd-K command palette.
/// Receives [AppLocalizations] so labels / keywords search in the user's
/// language. The shell concatenates every active domain's entries the
/// same way it merges device tools — see `defaultCommandPaletteEntries`.
typedef DomainCommandPaletteBuilder =
    List<CommandPaletteEntry> Function(AppLocalizations l10n);

/// Builds one domain's proposal applier route. Receives [Ref] so the
/// domain can resolve its concrete applier provider lazily.
typedef DomainProposalApplierRouteBuilder =
    Future<ProposalApplierRoute> Function(Ref ref);

/// Side-effecting bootstrap hook contributed by a domain. Use for app-start
/// provider reads that must stay alive for as long as the app container lives
/// (memory indexers, background scheduler registration, pending wakeup drains).
typedef DomainBootstrapBuilder = void Function(Ref ref);

/// Build-level provider overrides a domain contributes to composition
/// seams that are not yet represented by a narrower [DomainPack] field.
typedef DomainProviderOverridesBuilder = List<Override> Function();

/// Static description of one LifeOS domain's shell contributions. Held
/// next to the domain's tool barrel, so the inventory list in
/// `lib/app/domain_packs.dart` is the single grep-able answer to "what
/// domains does this build have?".
class DomainPack {
  const DomainPack({
    required this.scope,
    this.deviceTools = const <DeviceTool>[],
    this.toolDescriptors = const <String, ToolDescriptor>{},
    this.intentDescriptors = const <IntentDescriptor>[],
    this.proposalKinds = const <ProposalKindMeta>[],
    this.proposalApplierRouteBuilder,
    this.systemPromptBlock = '',
    this.shellSpecBuilder,
    this.shellRouteBuilder,
    this.deferredPreloader,
    this.tabPaths = const <String>[],
    this.additionalPathPrefixes = const <String>[],
    this.agentBuilder,
    this.memoryBootstrapBuilder,
    this.backgroundBootstrapBuilder,
    this.commandPaletteEntriesBuilder,
    this.providerOverridesBuilder,
  });

  /// Opt-in scope this pack registers under.
  final DomainScope scope;

  /// Device AI tools advertised when this domain is active.
  final List<DeviceTool> deviceTools;

  /// Metadata for [deviceTools], advertised when this domain is active.
  final Map<String, ToolDescriptor> toolDescriptors;

  /// AI object/capsule intents advertised when this domain is active.
  final List<IntentDescriptor> intentDescriptors;

  /// Chat proposal-card kinds advertised when this domain is active.
  final List<ProposalKindMeta> proposalKinds;

  /// Proposal apply/undo route owned by this domain. Null when the domain
  /// contributes no chat proposal-card apply kinds.
  final DomainProposalApplierRouteBuilder? proposalApplierRouteBuilder;

  /// System-prompt block appended onto [kDeviceSystemPromptBase].
  /// Empty string = no prompt contribution.
  final String systemPromptBlock;

  /// Localised shell spec (4-tab IA, color, dock placement). Null when
  /// the domain has no top-level shell presence yet.
  final DomainShellSpecBuilder? shellSpecBuilder;

  /// Constructs the domain's `StatefulShellRoute` (mounted under the
  /// outer `AppDockShell` in `router_builder.dart`). Null when the
  /// domain has no routable surface yet.
  final DomainShellRouteBuilder? shellRouteBuilder;

  /// Test-only preloader for every `deferred as` library this domain's
  /// routes can reach. Null when the domain ships no deferred libs.
  final DomainDeferredPreloader? deferredPreloader;

  /// Top-level tab paths the domain claims. Used by
  /// `domainForRoute` to map an active path back to its [scope] and
  /// by `primaryTabPathsProvider` to drive the system back handler
  /// + Cmd-1..4 tab switcher. The l10n-bound [shellSpecBuilder] still
  /// owns labels + icons.
  final List<String> tabPaths;

  /// Extra route prefixes the domain owns that are **not** top-level
  /// tabs (and therefore don't belong in [tabPaths]). Used only by
  /// `domainForRoute` for owner lookup; the system back handler does
  /// not treat these as primary roots. FinanceOS uses this for
  /// `/cashflow*` which lives under the Finance shell but isn't a
  /// 4-tab destination.
  final List<String> additionalPathPrefixes;

  /// Builds the per-turn list of [Agent]s. Null when the domain has no
  /// agents (e.g. FinanceOS today). Non-null builders typically read
  /// one or more agent providers from `ref` so each agent stays
  /// composition-blind.
  final DomainAgentBuilder? agentBuilder;

  /// Eager Memory Runtime indexer bootstrap. Null when the domain has no
  /// memory indexers with source streams.
  final DomainBootstrapBuilder? memoryBootstrapBuilder;

  /// Eager background-job bootstrap. Null when the domain has no startup
  /// background scheduler or pending wakeup drain.
  final DomainBootstrapBuilder? backgroundBootstrapBuilder;

  /// Cmd-K command palette contributions. Null when the domain has no
  /// palette entries yet. Non-null builders are invoked with the active
  /// locale's [AppLocalizations] and their entries are concatenated into
  /// the shell palette in domain order.
  final DomainCommandPaletteBuilder? commandPaletteEntriesBuilder;

  /// Build-level provider overrides for domain-owned seams that do not
  /// belong in `bootstrap.dart`. These are registered for every pack in
  /// the build inventory; opt-in-gated work should still check opt-ins
  /// inside the contributing provider.
  final DomainProviderOverridesBuilder? providerOverridesBuilder;
}

/// Inventory of all known [DomainPack]s. Default empty; `bootstrap.dart`
/// overrides this with the production list (`kAllDomainPacks`). Tests
/// can override with a subset to exercise shell behaviour with a
/// reduced domain matrix.
final domainPackRegistryProvider = Provider<List<DomainPack>>(
  (ref) => const <DomainPack>[],
);

/// Packs whose `scope` is in the user's opt-in set. Shell aggregators
/// (device tools, proposal kinds, proposal applier routes, system-prompt
/// blocks, agents, domain shells) all derive from this so the active-domain
/// calculation lives in exactly one place. Finance is always present —
/// [DomainOptIns] guarantees it in its constructor.
final activeDomainPacksProvider = Provider<List<DomainPack>>((ref) {
  final all = ref.watch(domainPackRegistryProvider);
  final optIns =
      ref.watch(domainOptInsProvider).value ?? DomainOptIns.financeOnly;
  return [
    for (final p in all)
      if (optIns.contains(p.scope)) p,
  ];
});
