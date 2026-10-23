/// LifeOS cross-domain registration seam (`docs/architecture/lifeos-shell.md` §4).
///
/// Each LifeOS domain (Finance / Health / Knowledge / future) declares
/// itself once as a [DomainPack] and registers into
/// [domainPackRegistryProvider]. The shell aggregators that used
/// to repeat the same opt-in branching (device tools, system-prompt
/// blocks, proposal kinds, proposal applier routes, shell specs, agent list,
/// memory indexers, background jobs, settings surfaces) all read this registry seam instead —
/// app composition needs one registry entry per domain. New domain identities
/// also require deliberate opt-in and client/backend sync namespace registration.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/theme/domain_accent.dart';
import '../../l10n/gen/app_localizations.dart';
import '../ai/agents/agent.dart';
import '../ai/agents/agent_presentation.dart';
import '../ai/composition/ai_context.dart';
import '../ai/composition/composite_proposal_applier.dart';
import '../ai/composition/proposal_kind_registry.dart';
import '../ai/contracts/tool_descriptor.dart';
import '../ai/intent/intent_policy.dart';
import '../ai/runtime/agent_runtime/agent_runtime_context_block.dart';
import '../ai/runtime/device/tools/device_tool.dart';
import '../auth/domain_scope.dart';
import '../auth/providers.dart';
import '../command_palette/command_palette_entry.dart';
import '../data_management/data_management.dart';
import '../shell/domain_shell.dart';
import 'life_signal.dart';
import 'share_intent.dart';

part 'domain_ai_contribution.dart';
part 'domain_shell_contribution.dart';
part 'domain_lifecycle_contribution.dart';
part 'domain_data_contribution.dart';

/// Builds the per-turn list of [Agent]s a domain contributes. Receives
/// [Ref] because most agents are themselves Riverpod-built (they depend
/// on runtime services like the LLM client or notification service).
typedef DomainAgentBuilder = List<Agent> Function(Ref ref);

/// Domain-owned prompt grounding. The app invokes only active packs selected
/// by the current route and isolates retrieval failures per contribution.
typedef DomainChatContextBuilder =
    Future<List<AgentRuntimeContextBlock>> Function(Ref ref, AiContext context);

/// Selects the bounded tool catalog exposed to the conversational Assistant
/// for the current route. Internal agent tools remain in [DomainAiContribution.deviceTools].
typedef DomainAssistantToolsBuilder = List<DeviceTool> Function(
  String currentPath,
);

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
typedef DomainCommandPaletteBuilder = List<CommandPaletteEntry> Function(
  AppLocalizations l10n,
);

/// Builds one domain's proposal applier route. Receives [Ref] so the
/// domain can resolve its concrete applier provider lazily.
typedef DomainProposalApplierRouteBuilder =
    Future<ProposalApplierRoute> Function(Ref ref);

/// Builds domain-owned rows for Settings -> Notifications.
typedef DomainNotificationSettingsBuilder = List<Widget> Function();

/// Side-effecting bootstrap hook contributed by a domain. Use for app-start
/// provider reads that must stay alive for as long as the app container lives
/// (memory indexers, background scheduler registration, pending wakeup drains).
typedef DomainBootstrapBuilder = void Function(Ref ref);

/// Build-level provider overrides a domain contributes to composition
/// seams that are not yet represented by a narrower [DomainPack] field.
typedef DomainProviderOverridesBuilder = List<Override> Function();

/// Builds the current bounded Life-hub signal slice for a domain.
typedef DomainLifeSignalBuilder = DomainLifeSignalSlice Function(
  Ref ref,
  DateTime now,
);

/// Resolves a source-preserving Execution reference owned by a domain.
typedef DomainSourceRouteResolver = String? Function(
  String rowFamily,
  String rowId,
);

/// Builds diagnostic local row counts for one domain.
typedef DomainLocalTableCountsBuilder = Future<Map<String, int>> Function(
  Ref ref,
);

/// Localized subtitle for the Settings → Domains toggle.
typedef DomainSettingsSubtitleBuilder = String Function(
  AppLocalizations l10n,
  bool enabled,
);

/// Wraps settings pages in router-level chrome such as `SystemBackScope`.
typedef DomainSettingsRouteWrapper = Widget Function(Widget child);

/// Builds top-level Settings child routes owned by a domain.
typedef DomainSettingsRoutesBuilder = List<RouteBase> Function(
  DomainSettingsRouteWrapper wrap,
);

/// Builds one domain's Settings → Domains detail route.
typedef DomainSettingsRouteBuilder = RouteBase Function(
  DomainSettingsRouteWrapper wrap,
);

/// Optional Settings → Domains contribution for an opt-in domain.
class DomainSettingsSpec {
  const DomainSettingsSpec({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.alwaysEnabled = false,
    this.detailPath,
    this.routeBuilder,
  }) : assert(
         (detailPath == null) == (routeBuilder == null),
         'detailPath and routeBuilder must be provided together',
       );

  /// Icon shown on the Settings → Domains toggle row.
  final IconData icon;

  /// User-facing domain label, e.g. `HealthOS`.
  final String label;

  /// Toggle subtitle that can vary with enabled state.
  final DomainSettingsSubtitleBuilder subtitle;

  /// Always-on domains show a status label instead of an opt-in switch.
  /// Operational controls belong in the detail page for every domain.
  final bool alwaysEnabled;

  /// Canonical path for the optional domain detail page. The Domains page
  /// uses this to push the detail route without knowing domain internals.
  final String? detailPath;

  /// Optional per-domain settings detail page route.
  final DomainSettingsRouteBuilder? routeBuilder;
}

/// Static description of one LifeOS domain's shell contributions. Held
/// next to the domain's tool barrel, so the inventory list in
/// `lib/app/domain_packs.dart` is the single grep-able answer to "what
/// domains does this build have?".
final class DomainPack {
  const DomainPack({
    required this.scope,
    this.ai = const DomainAiContribution(),
    this.shell = const DomainShellContribution(),
    this.lifecycle = const DomainLifecycleContribution(),
    this.data = const DomainDataContribution(),
  });

  final DomainScope scope;
  final DomainAiContribution ai;
  final DomainShellContribution shell;
  final DomainLifecycleContribution lifecycle;
  final DomainDataContribution data;
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

/// Resolves the accent color [scope] declares in [packs] for [brightness].
/// Null when the domain is unregistered or declares no accent — callers
/// fall back to `colors.primary`.
Color? resolveDomainAccent(
  List<DomainPack> packs,
  DomainScope scope,
  Brightness brightness,
) {
  for (final pack in packs) {
    if (pack.scope == scope) return pack.shell.accent?.resolve(brightness);
  }
  return null;
}

List<DomainShareIntentHandler> domainShareIntentHandlers(
  List<DomainPack> packs,
) {
  var index = 0;
  final indexed = <MapEntry<int, DomainShareIntentHandler>>[
    for (final pack in packs)
      for (final handler in pack.data.shareIntentHandlers)
        MapEntry(index++, handler),
  ];
  indexed.sort((a, b) {
    final priority = b.value.priority.compareTo(a.value.priority);
    if (priority != 0) return priority;
    return a.key.compareTo(b.key);
  });
  return [for (final entry in indexed) entry.value];
}
