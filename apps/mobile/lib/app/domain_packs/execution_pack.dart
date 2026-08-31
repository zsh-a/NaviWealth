import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/agents/agent_presentation.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/execution/agents/due_action_agent.dart'
    show kExecutionDueActionAgentId;
import 'package:naviwealth/features/execution/agents/providers.dart'
    as execution_agent_providers;
import 'package:naviwealth/features/execution/agents/review_agent.dart'
    show kExecutionReviewAgentId;
import 'package:naviwealth/features/execution/composition/execution_command_palette.dart';
import 'package:naviwealth/features/execution/composition/execution_domain_shell.dart';
import 'package:naviwealth/features/execution/composition/execution_proposal_applier.dart'
    as execution_proposals;
import 'package:naviwealth/features/execution/composition/execution_proposal_kinds.dart'
    show kExecutionProposalKinds;
import 'package:naviwealth/features/execution/composition/execution_routes.dart';
import 'package:naviwealth/features/execution/data/execution_memory_indexer.dart';
import 'package:naviwealth/features/execution/data_management/execution_data_management.dart';
import 'package:naviwealth/features/execution/execution_ai_tools.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../agent_runtime/overrides/agent_runtime_execution_overrides.dart';
import '../routing/route_paths.dart';
import 'execution_life_contribution.dart';
import 'proposal_applier_route.dart';

final DomainPack kExecutionPack = DomainPack(
  scope: DomainScope.execution,
  accent: DomainAccents.execution,
  deviceTools: kExecutionDeviceTools,
  assistantToolsBuilder: (_) => kExecutionAssistantDeviceTools,
  toolDescriptors: kExecutionToolDescriptors,
  intentDescriptors: kExecutionAgentIntentDescriptors,
  proposalKinds: kExecutionProposalKinds,
  proposalApplierRouteBuilder: (ref) => buildProposalApplierRoute(
    ref,
    readApplier: (ref) =>
        ref.watch(execution_proposals.executionProposalApplierProvider.future),
    kinds: execution_proposals.kExecutionProposalAppliedKinds,
    tablePrefixes: const {execution_proposals.kExecutionTablePrefix},
  ),
  systemPromptBlock: kExecutionSystemPromptBlock,
  shellSpecBuilder: executionDomainShell,
  shellRouteBuilder: executionShellRoute,
  tabPaths: [AppRoutes.executionToday, AppRoutes.executionPlans],
  reviewRoutePath: AppRoutes.executionReview,
  agentBuilder: _executionAgents,
  agentPresentationSpecs: const [
    AgentPresentationSpec(
      agentId: kExecutionReviewAgentId,
      domain: DomainScope.execution,
      icon: FLucideIcons.listChecks,
      label: _executionReviewLabel,
      description: _executionReviewDescription,
      userToggleable: false,
      visibleInSettings: false,
      placement: AgentResultPlacement.settingsOnly,
    ),
    AgentPresentationSpec(
      agentId: kExecutionDueActionAgentId,
      domain: DomainScope.execution,
      icon: FLucideIcons.alarmClock,
      label: _executionDueLabel,
      description: _executionDueDescription,
      userToggleable: false,
      visibleInSettings: false,
      placement: AgentResultPlacement.settingsOnly,
    ),
  ],
  memorySourcePrefixes: const ['exec:', 'execution:'],
  memoryBootstrapBuilder: _executionMemoryBootstrap,
  backgroundBootstrapBuilder: _executionBackgroundBootstrap,
  commandPaletteEntriesBuilder: executionCommandPaletteEntries,
  providerOverridesBuilder: agentRuntimeExecutionProviderOverrides,
  lifeSignalBuilder: executionLifeSignals,
  sourceRouteResolver: executionSourceRouteContribution,
  dataManagementSpec: executionDataManagementSpec,
  settingsSpec: const DomainSettingsSpec(
    icon: FLucideIcons.listTodo,
    label: 'ExecutionOS',
    subtitle: _executionSettingsSubtitle,
  ),
);

List<Agent> _executionAgents(Ref ref) =>
    ref.watch(execution_agent_providers.executionAgentsProvider);

void _executionMemoryBootstrap(Ref ref) {
  ref.watch(executionMemoryIndexerProvider);
}

void _executionBackgroundBootstrap(Ref ref) {
  ref.watch(execution_agent_providers.executionReviewCronProvider);
  unawaited(
    ref.read(
      execution_agent_providers.pendingExecutionReviewRunProvider.future,
    ),
  );
}

String _executionSettingsSubtitle(AppLocalizations l10n, bool enabled) =>
    enabled
    ? l10n.settingsDomainsExecutionEnabledSubtitle
    : l10n.settingsDomainsExecutionDisabledSubtitle;

String _executionReviewLabel(AppLocalizations l10n) =>
    l10n.agentPresentationExecutionReviewLabel;

String _executionReviewDescription(AppLocalizations l10n) =>
    l10n.agentPresentationExecutionReviewDescription;

String _executionDueLabel(AppLocalizations l10n) => l10n.executionDueAgentTitle;

String _executionDueDescription(AppLocalizations l10n) =>
    l10n.executionDueAgentDescription;
