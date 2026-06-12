/// LifeOS domain-pack composition bundle.
///
/// `bootstrap.dart` owns app-level wiring, but it should not repeat the
/// same active-pack loops for tools, proposal kinds/routes, prompts, agents,
/// shells, and Cmd-K. This file keeps those aggregations together so adding
/// a domain stays a registry change plus domain-local contributions.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../core/ai/agents/agent.dart';
import '../core/ai/agents/agent_registry.dart';
import '../core/ai/composition/composite_proposal_applier.dart';
import '../core/ai/composition/device_tools_provider.dart';
import '../core/ai/composition/proposal_applier.dart';
import '../core/ai/composition/proposal_kind_registry.dart';
import '../core/ai/composition/system_prompt_blocks.dart';
import '../core/ai/composition/tool_descriptor_lookup.dart';
import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/runtime/device/tools/device_tool.dart';
import '../core/ai/runtime/device/tools/device_tool_registry.dart'
    show kShellDeviceToolsCore, kShellToolDescriptors;
import '../core/command_palette/command_palette_entry.dart';
import '../core/lifeos/domain_pack.dart';
import '../core/shell/domain_shell.dart';
import '../l10n/gen/app_localizations.dart';
import 'domain_packs.dart';

List<Override> lifeOsDomainCompositionOverrides({
  List<DomainPack> packs = kAllDomainPacks,
}) {
  return [
    domainPackRegistryProvider.overrideWith((ref) => packs),
    deviceToolsProvider.overrideWith(
      (ref) => domainDeviceTools(ref.watch(activeDomainPacksProvider)),
    ),
    toolDescriptorLookupProvider.overrideWith((ref) {
      final descriptors = domainToolDescriptors(
        ref.watch(activeDomainPacksProvider),
      );
      return (name) => descriptors[name];
    }),
    proposalKindRegistryProvider.overrideWith(
      (ref) => domainProposalKinds(ref.watch(activeDomainPacksProvider)),
    ),
    proposalApplierProvider.overrideWith((ref) async {
      final routes = await domainProposalApplierRoutes(
        ref,
        ref.watch(activeDomainPacksProvider),
      );
      return CompositeProposalApplier(routes: routes);
    }),
    systemPromptBlocksProvider.overrideWith(
      (ref) => domainSystemPromptBlocks(ref.watch(activeDomainPacksProvider)),
    ),
    agentRegistryProvider.overrideWith(
      (ref) => domainAgents(ref, ref.watch(activeDomainPacksProvider)),
    ),
    activeDomainShellsProvider.overrideWith((ref) {
      // The spec depends on AppLocalizations for labels, which is resolved
      // per-render inside the shell. Bootstrap builds with the default
      // locale here; the widget tree reapplies the active locale via
      // Riverpod invalidation.
      final l10n = lookupAppLocalizations(const Locale('en'));
      return domainShellSpecs(ref.watch(activeDomainPacksProvider), l10n);
    }),
  ];
}

List<DeviceTool> domainDeviceTools(List<DomainPack> packs) {
  return <DeviceTool>[
    ...kShellDeviceToolsCore,
    for (final p in packs) ...p.deviceTools,
  ];
}

Map<String, ToolDescriptor> domainToolDescriptors(List<DomainPack> packs) {
  return <String, ToolDescriptor>{
    ...kShellToolDescriptors,
    for (final p in packs) ...p.toolDescriptors,
  };
}

List<ProposalKindMeta> domainProposalKinds(List<DomainPack> packs) {
  return [for (final p in packs) ...p.proposalKinds];
}

Future<List<ProposalApplierRoute>> domainProposalApplierRoutes(
  Ref ref,
  List<DomainPack> packs,
) async {
  final routes = <ProposalApplierRoute>[];
  for (final p in packs) {
    final builder = p.proposalApplierRouteBuilder;
    if (builder != null) routes.add(await builder(ref));
  }
  return routes;
}

List<String> domainSystemPromptBlocks(List<DomainPack> packs) {
  return [
    for (final p in packs)
      if (p.systemPromptBlock.isNotEmpty) p.systemPromptBlock,
  ];
}

List<Agent> domainAgents(Ref ref, List<DomainPack> packs) {
  return [
    for (final p in packs)
      if (p.agentBuilder != null) ...p.agentBuilder!(ref),
  ];
}

List<DomainShellSpec> domainShellSpecs(
  List<DomainPack> packs,
  AppLocalizations l10n,
) {
  return [
    for (final p in packs)
      if (p.shellSpecBuilder != null) p.shellSpecBuilder!(l10n),
  ];
}

List<CommandPaletteEntry> domainCommandPaletteEntries(
  List<DomainPack> packs,
  AppLocalizations l10n,
) {
  return [
    for (final p in packs)
      if (p.commandPaletteEntriesBuilder != null)
        ...p.commandPaletteEntriesBuilder!(l10n),
  ];
}
