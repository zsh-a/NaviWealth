/// Inventory of LifeOS domains (`docs/architecture/lifeos-shell.md` §4).
///
/// One entry per domain — adding a new LifeOS domain means landing
/// its tool barrel + shell spec + routes + agents under
/// `features/<domain>/`, then appending one [DomainPack] entry here.
/// `bootstrap.dart` registers this list as
/// [domainPackRegistryProvider]; the shell aggregators (device tools,
/// prompt blocks, proposal kinds, proposal applier routes, shell specs, agent
/// registry, memory/background bootstraps, router branches, primary tab paths,
/// test preloaders) derive from it automatically.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/ai/agents/agent.dart';
import '../core/ai/composition/composite_proposal_applier.dart';
import '../core/auth/domain_scope.dart';
import '../core/lifeos/domain_pack.dart';
import '../features/execution/agents/providers.dart'
    as execution_agent_providers;
import '../features/execution/composition/execution_command_palette.dart';
import '../features/execution/composition/execution_domain_shell.dart';
import '../features/execution/composition/execution_proposal_applier.dart'
    as execution_proposals;
import '../features/execution/composition/execution_proposal_kinds.dart'
    show kExecutionProposalKinds;
import '../features/execution/composition/execution_routes.dart';
import '../features/execution/data/execution_memory_indexer.dart';
import '../features/execution_ai_tools.dart';
import '../features/finance/composition/finance_bootstrap.dart';
import '../features/finance/composition/finance_command_palette.dart';
import '../features/finance/composition/finance_intents.dart';
import '../features/finance/composition/finance_proposal_applier.dart'
    as finance_proposals;
import '../features/finance/composition/finance_proposal_kinds.dart'
    show kFinanceProposalKinds;
import '../features/finance/composition/finance_routes.dart';
import '../features/finance_ai_tools.dart';
import '../features/finance_domain_shell.dart';
import '../features/health/agents/morning_briefing_agent.dart';
import '../features/health/agents/providers.dart' as health_agent_providers;
import '../features/health/agents/recovery_alert_agent.dart';
import '../features/health/agents/weekly_summary_agent.dart';
import '../features/health/composition/health_command_palette.dart';
import '../features/health/composition/health_domain_shell.dart';
import '../features/health/composition/health_routes.dart';
import '../features/health/data/health_metric_memory_indexer.dart';
import '../features/health_ai_tools.dart';
import '../features/knowledge/agents/providers.dart'
    as knowledge_agent_providers;
import '../features/knowledge/composition/knowledge_command_palette.dart';
import '../features/knowledge/composition/knowledge_domain_shell.dart';
import '../features/knowledge/composition/knowledge_proposal_applier.dart'
    as knowledge_proposals;
import '../features/knowledge/composition/knowledge_proposal_kinds.dart'
    show kKnowledgeProposalKinds;
import '../features/knowledge/composition/knowledge_routes.dart';
import '../features/knowledge/data/knowledge_decision_memory_indexer.dart';
import '../features/knowledge/data/knowledge_object_memory_indexers.dart';
import '../features/knowledge_ai_tools.dart';
import '../features/options_income/data/trade_journal_memory_indexer.dart';
import '../features/settings/ui/execution_domain_settings_page.dart';
import '../features/settings/ui/health_domain_settings_page.dart';
import '../features/settings/ui/knowledge_domain_settings_page.dart';
import '../l10n/gen/app_localizations.dart';
import 'agent_runtime/agent_runtime_execution_overrides.dart';
import 'agent_runtime/agent_runtime_health_overrides.dart';
import 'agent_runtime/agent_runtime_knowledge_overrides.dart';
import 'route_paths.dart';

final DomainPack kFinancePack = DomainPack(
  scope: DomainScope.finance,
  deviceTools: kFinanceDeviceTools,
  toolDescriptors: kFinanceToolDescriptors,
  intentDescriptors: kFinanceIntentDescriptors,
  proposalKinds: kFinanceProposalKinds,
  proposalApplierRouteBuilder: _financeProposalApplierRoute,
  systemPromptBlock: kFinanceSystemPromptBlock,
  shellSpecBuilder: financeDomainShell,
  shellRouteBuilder: financeShellRoute,
  deferredPreloader: preloadFinanceDeferredRoutesForTest,
  tabPaths: [
    AppRoutes.home,
    AppRoutes.activity,
    AppRoutes.wealth,
    AppRoutes.plan,
  ],
  // `/cashflow*` is reachable from the Finance shell (cashflow page +
  // recurring + dividends) but isn't a primary tab — it's surfaced
  // through Wealth / Plan navigation. Listing it here keeps
  // `aiContextProvider` aware that those routes belong to Finance.
  additionalPathPrefixes: [AppRoutes.cashflow],
  memoryBootstrapBuilder: _financeMemoryBootstrap,
  backgroundBootstrapBuilder: financeBackgroundBootstrap,
  commandPaletteEntriesBuilder: financeCommandPaletteEntries,
  providerOverridesBuilder: financeCompositionOverrides,
);

final DomainPack kHealthPack = DomainPack(
  scope: DomainScope.health,
  deviceTools: kHealthDeviceTools,
  toolDescriptors: kHealthToolDescriptors,
  systemPromptBlock: kHealthSystemPromptBlock,
  shellSpecBuilder: healthDomainShell,
  shellRouteBuilder: healthShellRoute,
  deferredPreloader: preloadHealthDeferredRoutesForTest,
  tabPaths: [
    AppRoutes.healthToday,
    AppRoutes.healthTrend,
    AppRoutes.healthPlan,
  ],
  agentBuilder: _healthAgents,
  memoryBootstrapBuilder: _healthMemoryBootstrap,
  backgroundBootstrapBuilder: _healthBackgroundBootstrap,
  commandPaletteEntriesBuilder: healthCommandPaletteEntries,
  providerOverridesBuilder: agentRuntimeHealthProviderOverrides,
  settingsSpec: _domainSettingsSpec(
    icon: FLucideIcons.heartPulse,
    label: 'HealthOS',
    subtitle: _healthSettingsSubtitle,
    routePath: AppRoutes.settingsDomainsHealth,
    routeName: AppRouteNames.domainsHealth,
    page: const HealthDomainSettingsPage(),
  ),
);

final DomainPack kKnowledgePack = DomainPack(
  scope: DomainScope.knowledge,
  deviceTools: kKnowledgeDeviceTools,
  toolDescriptors: kKnowledgeToolDescriptors,
  proposalKinds: kKnowledgeProposalKinds,
  proposalApplierRouteBuilder: _knowledgeProposalApplierRoute,
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
  settingsSpec: _domainSettingsSpec(
    icon: FLucideIcons.brain,
    label: 'KnowledgeOS',
    subtitle: _knowledgeSettingsSubtitle,
    routePath: AppRoutes.settingsDomainsKnowledge,
    routeName: AppRouteNames.domainsKnowledge,
    page: const KnowledgeDomainSettingsPage(),
  ),
);

final DomainPack kExecutionPack = DomainPack(
  scope: DomainScope.execution,
  deviceTools: kExecutionDeviceTools,
  toolDescriptors: kExecutionToolDescriptors,
  proposalKinds: kExecutionProposalKinds,
  proposalApplierRouteBuilder: _executionProposalApplierRoute,
  systemPromptBlock: kExecutionSystemPromptBlock,
  shellSpecBuilder: executionDomainShell,
  shellRouteBuilder: executionShellRoute,
  tabPaths: [
    AppRoutes.executionToday,
    AppRoutes.executionCommitments,
    AppRoutes.executionReview,
  ],
  agentBuilder: _executionAgents,
  memoryBootstrapBuilder: _executionMemoryBootstrap,
  commandPaletteEntriesBuilder: executionCommandPaletteEntries,
  providerOverridesBuilder: agentRuntimeExecutionProviderOverrides,
  settingsSpec: _domainSettingsSpec(
    icon: FLucideIcons.listTodo,
    label: 'ExecutionOS',
    subtitle: _executionSettingsSubtitle,
    routePath: AppRoutes.settingsDomainsExecution,
    routeName: AppRouteNames.domainsExecution,
    page: const ExecutionDomainSettingsPage(),
  ),
);

/// Production inventory. `bootstrap.dart` overrides
/// [domainPackRegistryProvider] with this list. Tests can override
/// with a subset for reduced-matrix scenarios.
final List<DomainPack> kAllDomainPacks = <DomainPack>[
  kFinancePack,
  kHealthPack,
  kKnowledgePack,
  kExecutionPack,
];

List<Agent> _healthAgents(Ref ref) => <Agent>[
  ref.watch(morningBriefingAgentProvider),
  ref.watch(recoveryAlertAgentProvider),
  ref.watch(weeklySummaryAgentProvider),
];

List<Agent> _knowledgeAgents(Ref ref) =>
    ref.watch(knowledge_agent_providers.knowledgeAgentsProvider);

List<Agent> _executionAgents(Ref ref) =>
    ref.watch(execution_agent_providers.executionAgentsProvider);

void _financeMemoryBootstrap(Ref ref) {
  ref.watch(tradeJournalMemoryIndexerProvider);
}

void _healthMemoryBootstrap(Ref ref) {
  ref.watch(healthMetricMemoryIndexerProvider);
}

void _knowledgeMemoryBootstrap(Ref ref) {
  ref.watch(knowledgeDecisionMemoryIndexerProvider);
  ref.watch(knowledgeNoteMemoryIndexerProvider);
  ref.watch(knowledgePrincipleMemoryIndexerProvider);
  ref.watch(knowledgeAssumptionMemoryIndexerProvider);
  ref.watch(knowledgeConceptMemoryIndexerProvider);
  ref.watch(knowledgeExperimentMemoryIndexerProvider);
  ref.watch(knowledgeRoutineMemoryIndexerProvider);
}

void _executionMemoryBootstrap(Ref ref) {
  ref.watch(executionMemoryIndexerProvider);
}

void _healthBackgroundBootstrap(Ref ref) {
  ref.watch(health_agent_providers.morningBriefingCronProvider);
  ref.watch(health_agent_providers.garminSyncCronProvider);
  ref.watch(health_agent_providers.healthPlatformSyncCronProvider);
  unawaited(ref.read(health_agent_providers.pendingBriefingRunProvider.future));
  unawaited(
    ref.read(health_agent_providers.pendingGarminSyncRunProvider.future),
  );
  unawaited(
    ref.read(
      health_agent_providers.pendingHealthPlatformSyncRunProvider.future,
    ),
  );
}

DomainSettingsSpec _domainSettingsSpec({
  required IconData icon,
  required String label,
  required DomainSettingsSubtitleBuilder subtitle,
  required String routePath,
  required String routeName,
  required Widget page,
}) {
  return DomainSettingsSpec(
    icon: icon,
    label: label,
    subtitle: subtitle,
    routeBuilder: (wrap) => GoRoute(
      path: _settingsChildPath(routePath),
      name: routeName,
      builder: (context, state) => wrap(page),
    ),
  );
}

String _settingsChildPath(String absolutePath) {
  const prefix = '${AppRoutes.settings}/';
  if (!absolutePath.startsWith(prefix)) {
    throw ArgumentError.value(
      absolutePath,
      'absolutePath',
      'must be under ${AppRoutes.settings}',
    );
  }
  return absolutePath.substring(prefix.length);
}

String _healthSettingsSubtitle(AppLocalizations l10n, bool enabled) => enabled
    ? l10n.settingsDomainsHealthEnabledSubtitle
    : l10n.settingsDomainsHealthDisabledSubtitle;

String _knowledgeSettingsSubtitle(AppLocalizations l10n, bool enabled) =>
    enabled
    ? l10n.settingsDomainsKnowledgeEnabledSubtitle
    : l10n.settingsDomainsKnowledgeDisabledSubtitle;

String _executionSettingsSubtitle(AppLocalizations l10n, bool enabled) =>
    enabled
    ? l10n.settingsDomainsExecutionEnabledSubtitle
    : l10n.settingsDomainsExecutionDisabledSubtitle;

Future<ProposalApplierRoute> _financeProposalApplierRoute(Ref ref) async {
  final applier = await ref.watch(
    finance_proposals.financeProposalApplierProvider.future,
  );
  return ProposalApplierRoute(
    applier: applier,
    kinds: finance_proposals.kFinanceProposalAppliedKinds,
    tablePrefixes: finance_proposals.kFinanceProposalAppliedTablePrefixes,
  );
}

Future<ProposalApplierRoute> _knowledgeProposalApplierRoute(Ref ref) async {
  final applier = await ref.watch(
    knowledge_proposals.knowledgeProposalApplierProvider.future,
  );
  return ProposalApplierRoute(
    applier: applier,
    kinds: knowledge_proposals.kKnowledgeProposalAppliedKinds,
    tablePrefixes: const {knowledge_proposals.kKnowledgeTablePrefix},
  );
}

Future<ProposalApplierRoute> _executionProposalApplierRoute(Ref ref) async {
  final applier = await ref.watch(
    execution_proposals.executionProposalApplierProvider.future,
  );
  return ProposalApplierRoute(
    applier: applier,
    kinds: execution_proposals.kExecutionProposalAppliedKinds,
    tablePrefixes: const {execution_proposals.kExecutionTablePrefix},
  );
}
