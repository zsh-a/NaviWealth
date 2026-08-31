import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_command_palette.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_domain_shell.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_proposal_applier.dart'
    as knowledge_proposals;
import 'package:naviwealth/features/knowledge/composition/knowledge_proposal_kinds.dart'
    show kKnowledgeProposalKinds;
import 'package:naviwealth/features/knowledge/composition/knowledge_routes.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_share_intent_handler.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_decision_memory_indexer.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_note_memory_indexer.dart';
import 'package:naviwealth/features/knowledge/data_management/knowledge_data_management.dart';
import 'package:naviwealth/features/knowledge/knowledge_ai_tools.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../routing/route_paths.dart';
import 'knowledge_source_routes.dart';
import 'proposal_applier_route.dart';

final DomainPack kKnowledgePack = DomainPack(
  scope: DomainScope.knowledge,
  accent: DomainAccents.knowledge,
  deviceTools: kKnowledgeDeviceTools,
  assistantToolsBuilder: (_) => kKnowledgeAssistantDeviceTools,
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
  tabPaths: [AppRoutes.knowledgeInbox, AppRoutes.knowledgeLibrary],
  memorySourcePrefixes: const ['know:'],
  memoryBootstrapBuilder: _knowledgeMemoryBootstrap,
  commandPaletteEntriesBuilder: knowledgeCommandPaletteEntries,
  sourceRouteResolver: knowledgeSourceRoute,
  shareIntentHandlers: const [KnowledgeShareIntentHandler()],
  dataManagementSpec: knowledgeDataManagementSpec,
  settingsSpec: const DomainSettingsSpec(
    icon: FLucideIcons.brain,
    label: 'KnowledgeOS',
    subtitle: _knowledgeSettingsSubtitle,
  ),
);

void _knowledgeMemoryBootstrap(Ref ref) {
  ref.watch(knowledgeDecisionMemoryIndexerProvider);
  ref.watch(knowledgeNoteMemoryIndexerProvider);
}

String _knowledgeSettingsSubtitle(AppLocalizations l10n, bool enabled) =>
    enabled
    ? l10n.settingsDomainsKnowledgeEnabledSubtitle
    : l10n.settingsDomainsKnowledgeDisabledSubtitle;
