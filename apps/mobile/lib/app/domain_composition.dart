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
import '../core/ai/composition/batch_proposal_undo.dart';
import '../core/ai/composition/composite_proposal_applier.dart';
import '../core/ai/composition/device_tools_provider.dart';
import '../core/ai/composition/proposal_applier.dart';
import '../core/ai/composition/proposal_apply_state.dart';
import '../core/ai/composition/proposal_kind_registry.dart';
import '../core/ai/composition/system_prompt_blocks.dart';
import '../core/ai/composition/tool_descriptor_lookup.dart';
import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/intent/intent.dart';
import '../core/ai/runtime/device/tools/device_tool.dart';
import '../core/ai/runtime/device/tools/device_tool_registry.dart'
    show kShellDeviceToolsCore, kShellToolDescriptors;
import '../core/ai/write/persisted_undo_dispatcher.dart';
import '../core/auth/domain_scope.dart';
import '../core/auth/providers.dart' as auth_providers;
import '../core/command_palette/command_palette_entry.dart';
import '../core/lifeos/domain_pack.dart';
import '../core/shell/domain_shell.dart';
import '../core/shell/entity_route_resolver.dart';
import '../design_system/preferences/theme_preferences.dart';
import '../features/ai_chat/data/providers.dart' as ai_chat_providers;
import '../features/finance/composition/finance_route_paths.dart';
import '../l10n/gen/app_localizations.dart';
import 'domain_packs.dart';
import 'shell_chrome.dart';

List<Override> lifeOsDomainCompositionOverrides({List<DomainPack>? packs}) {
  final resolvedPacks = packs ?? kAllDomainPacks;
  return [
    ...appShellChromeOverrides(),
    domainPackRegistryProvider.overrideWith((ref) => resolvedPacks),
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
    intentCatalogProvider.overrideWith(
      (ref) => domainIntentCatalog(ref.watch(activeDomainPacksProvider)),
    ),
    proposalApplierProvider.overrideWith((ref) async {
      final routes = await domainProposalApplierRoutes(
        ref,
        ref.watch(activeDomainPacksProvider),
      );
      return CompositeProposalApplier(routes: routes);
    }),
    persistedUndoRevertersProvider.overrideWith((ref) {
      return appPersistedUndoReverters(ref);
    }),
    systemPromptBlocksProvider.overrideWith(
      (ref) => domainSystemPromptBlocks(ref.watch(activeDomainPacksProvider)),
    ),
    agentRegistryProvider.overrideWith(
      (ref) => domainAgents(ref, ref.watch(activeDomainPacksProvider)),
    ),
    activeDomainShellsProvider.overrideWith((ref) {
      final l10n = lookupAppLocalizations(
        _resolvedShellLocale(ref.watch(localeProvider)),
      );
      return domainShellSpecs(ref.watch(activeDomainPacksProvider), l10n);
    }),
    entityRouteResolverProvider.overrideWith((_) => appEntityRouteResolver),
    auth_providers.authTokenDomainsProvider.overrideWith((ref) {
      return (ref.watch(auth_providers.domainOptInsProvider).value ??
              DomainOptIns.financeOnly)
          .toWire();
    }),
    ...domainProviderOverrides(resolvedPacks),
  ];
}

String? appEntityRouteResolver(EntityRouteRef ref) {
  return switch (ref.entityTable) {
    EntityRouteTables.assets => FinanceRoutes.wealthAsset(ref.entityId),
    EntityRouteTables.accounts => FinanceRoutes.wealthAccount(ref.entityId),
    EntityRouteTables.liabilities => FinanceRoutes.wealthLiability(
      ref.entityId,
    ),
    EntityRouteTables.journalEntries => FinanceRoutes.activityEntry(
      ref.entityId,
    ),
    EntityRouteTables.optionsTradeJournal => FinanceRoutes.planIncome,
    _ => null,
  };
}

Map<String, PersistedUndoReverter> appPersistedUndoReverters(Ref ref) {
  return <String, PersistedUndoReverter>{
    kBatchProposalUndoKind: (entry) async {
      final applier = await ref.read(proposalApplierProvider.future);
      final children = batchProposalUndoChildren(entry.payload);
      for (final childState in children.reversed) {
        await applier.undo(childState);
      }

      final sessionId = entry.payload['chat_session_id'] as String?;
      final messageId = entry.payload['chat_message_id'] as String?;
      final toolInvocationId =
          entry.payload['chat_tool_invocation_id'] as String?;
      if (sessionId == null || messageId == null || toolInvocationId == null) {
        return;
      }

      final repo = await ref.read(
        ai_chat_providers.chatRepositoryProvider.future,
      );
      await repo.updateToolApplyState(
        sessionId: sessionId,
        messageId: messageId,
        toolInvocationId: toolInvocationId,
        newState: ProposalApplyState(
          status: ProposalApplyStatus.undone,
          appliedTable: kBatchProposalAppliedTable,
          appliedAt: entry.createdAt,
          undoData: <String, Object?>{
            'proposal_id': entry.payload['proposal_id'],
            'child_count': children.length,
          },
          undoToken: entry.token,
          shortLabel: entry.payload['summary_zh'] as String?,
        ),
      );
    },
  };
}

Locale _resolvedShellLocale(Locale? preferred) {
  final locale = preferred ?? WidgetsBinding.instance.platformDispatcher.locale;
  for (final supported in AppLocalizations.supportedLocales) {
    if (supported.languageCode == locale.languageCode) {
      return supported;
    }
  }
  return const Locale('en');
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

IntentCatalog domainIntentCatalog(List<DomainPack> packs) {
  return IntentCatalog([for (final p in packs) ...p.intentDescriptors]);
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
    for (final registration in domainAgentRegistrations(ref, packs))
      registration.agent,
  ];
}

List<DomainAgentRegistration> domainAgentRegistrations(
  Ref ref,
  List<DomainPack> packs,
) {
  return [
    for (final p in packs)
      if (p.agentBuilder != null)
        for (final agent in p.agentBuilder!(ref))
          DomainAgentRegistration(agent: agent, domain: p.scope),
  ];
}

void domainMemoryBootstraps(Ref ref, List<DomainPack> packs) {
  for (final p in packs) {
    p.memoryBootstrapBuilder?.call(ref);
  }
}

void domainBackgroundBootstraps(Ref ref, List<DomainPack> packs) {
  for (final p in packs) {
    p.backgroundBootstrapBuilder?.call(ref);
  }
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

List<Override> domainProviderOverrides(List<DomainPack> packs) {
  return [
    for (final p in packs)
      if (p.providerOverridesBuilder != null) ...p.providerOverridesBuilder!(),
  ];
}
