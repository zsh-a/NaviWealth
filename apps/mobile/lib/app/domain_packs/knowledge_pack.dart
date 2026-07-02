import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/ai/agents/agent.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../core/shell/settings_route_paths.dart';
import '../../features/knowledge/agents/providers.dart'
    as knowledge_agent_providers;
import '../../features/knowledge/composition/knowledge_command_palette.dart';
import '../../features/knowledge/composition/knowledge_domain_shell.dart';
import '../../features/knowledge/composition/knowledge_proposal_applier.dart'
    as knowledge_proposals;
import '../../features/knowledge/composition/knowledge_proposal_kinds.dart'
    show kKnowledgeProposalKinds;
import '../../features/knowledge/composition/knowledge_routes.dart';
import '../../features/knowledge/data/knowledge_decision_memory_indexer.dart';
import '../../features/knowledge/data/knowledge_object_memory_indexers.dart';
import '../../features/knowledge/ui/knowledge_domain_settings_page.dart';
import '../../features/knowledge_ai_tools.dart';
import '../../l10n/gen/app_localizations.dart';
import '../agent_runtime/agent_runtime_knowledge_overrides.dart';
import '../route_paths.dart';
import 'domain_settings_spec.dart';
import 'proposal_applier_route.dart';

final DomainPack kKnowledgePack = DomainPack(
  scope: DomainScope.knowledge,
  deviceTools: kKnowledgeDeviceTools,
  toolDescriptors: kKnowledgeToolDescriptors,
  proposalKinds: kKnowledgeProposalKinds,
  proposalApplierRouteBuilder: (ref) => buildProposalApplierRoute(
    ref,
    readApplier: (ref) =>
        ref.watch(knowledge_proposals.knowledgeProposalApplierProvider.future),
    kinds: knowledge_proposals.kKnowledgeProposalAppliedKinds,
    tablePrefixes: const {knowledge_proposals.kKnowledgeTablePrefix},
  ),
  systemPromptBlock: kKnowledgeSystemPromptBlock,
  shellSpecBuilder: knowledgeDomainShell,
  shellRouteBuilder: knowledgeShellRoute,
  tabPaths: [
    AppRoutes.knowledgeInbox,
    AppRoutes.knowledgeLibrary,
    AppRoutes.knowledgeReview,
  ],
  agentBuilder: _knowledgeAgents,
  memoryBootstrapBuilder: _knowledgeMemoryBootstrap,
  commandPaletteEntriesBuilder: knowledgeCommandPaletteEntries,
  providerOverridesBuilder: agentRuntimeKnowledgeProviderOverrides,
  settingsSpec: domainSettingsSpec(
    icon: FLucideIcons.brain,
    label: 'KnowledgeOS',
    subtitle: _knowledgeSettingsSubtitle,
    routePath: SettingsRoutes.domainsKnowledge,
    routeName: SettingsRouteNames.domainsKnowledge,
    page: const KnowledgeDomainSettingsPage(),
  ),
);

List<Agent> _knowledgeAgents(Ref ref) =>
    ref.watch(knowledge_agent_providers.knowledgeAgentsProvider);

void _knowledgeMemoryBootstrap(Ref ref) {
  ref.watch(knowledgeDecisionMemoryIndexerProvider);
  ref.watch(knowledgeNoteMemoryIndexerProvider);
  ref.watch(knowledgePrincipleMemoryIndexerProvider);
  ref.watch(knowledgeAssumptionMemoryIndexerProvider);
  ref.watch(knowledgeConceptMemoryIndexerProvider);
  ref.watch(knowledgeExperimentMemoryIndexerProvider);
  ref.watch(knowledgeRoutineMemoryIndexerProvider);
}

String _knowledgeSettingsSubtitle(AppLocalizations l10n, bool enabled) =>
    enabled
    ? l10n.settingsDomainsKnowledgeEnabledSubtitle
    : l10n.settingsDomainsKnowledgeDisabledSubtitle;
