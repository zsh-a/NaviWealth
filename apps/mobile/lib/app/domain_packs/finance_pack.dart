import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/agents/agent_presentation.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/shell/settings_route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/agents/cashflow_anomaly_review_agent.dart'
    show kCashflowAnomalyReviewAgentId;
import 'package:naviwealth/features/finance/agents/fire_plan_drift_monitor_agent.dart'
    show kFirePlanDriftMonitorAgentId;
import 'package:naviwealth/features/finance/agents/options_income_risk_review_agent.dart'
    show kOptionsIncomeRiskReviewAgentId;
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/agents/weekly_wealth_review_agent.dart'
    show kWeeklyWealthReviewAgentId;
import 'package:naviwealth/features/finance/composition/finance_bootstrap.dart';
import 'package:naviwealth/features/finance/composition/finance_command_palette.dart';
import 'package:naviwealth/features/finance/composition/finance_domain_shell.dart';
import 'package:naviwealth/features/finance/composition/finance_intents.dart';
import 'package:naviwealth/features/finance/composition/finance_proposal_applier.dart'
    as finance_proposals;
import 'package:naviwealth/features/finance/composition/finance_proposal_kinds.dart'
    show kFinanceProposalKinds;
import 'package:naviwealth/features/finance/composition/finance_routes.dart';
import 'package:naviwealth/features/finance/composition/finance_settings_routes.dart';
import 'package:naviwealth/features/finance/composition/finance_share_intent_handler.dart';
import 'package:naviwealth/features/finance/data/diagnostics/local_table_counts.dart';
import 'package:naviwealth/features/finance/data_management/finance_data_management.dart';
import 'package:naviwealth/features/finance/finance_ai_tools.dart';
import 'package:naviwealth/features/finance/options_income/data/trade_journal_memory_indexer.dart';
import 'package:naviwealth/features/finance/ui/settings/finance_settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../features/finance/composition/finance_chat_context.dart';
import '../routing/route_paths.dart';
import 'domain_settings_spec.dart';
import 'finance_life_contribution.dart';
import 'proposal_applier_route.dart';

final DomainPack kFinancePack = DomainPack(
  scope: DomainScope.finance,
  ai: DomainAiContribution(
    deviceTools: kFinanceDeviceTools,
    assistantToolsBuilder: financeAssistantToolsForPath,
    chatContextBuilder: buildFinanceChatContextBlocks,
    toolDescriptors: kFinanceToolDescriptors,
    intentDescriptors: [
      ...kFinanceIntentDescriptors,
      ...kFinanceAgentIntentDescriptors,
    ],
    proposalKinds: kFinanceProposalKinds,
    proposalApplierRouteBuilder: (ref) => buildProposalApplierRoute(
      ref,
      readApplier: (ref) =>
          ref.watch(finance_proposals.financeProposalApplierProvider.future),
      kinds: finance_proposals.kFinanceProposalAppliedKinds,
      tablePrefixes: finance_proposals.kFinanceProposalAppliedTablePrefixes,
    ),
    systemPromptBlock: kFinanceSystemPromptBlock,
    agentBuilder: _financeAgents,
    agentPresentationSpecs: const [
      AgentPresentationSpec(
        agentId: kWeeklyWealthReviewAgentId,
        domain: DomainScope.finance,
        icon: FLucideIcons.walletCards,
        label: _weeklyWealthReviewLabel,
        description: _weeklyWealthReviewDescription,
        placement: AgentResultPlacement.domainHome,
      ),
      AgentPresentationSpec(
        agentId: kCashflowAnomalyReviewAgentId,
        domain: DomainScope.finance,
        icon: FLucideIcons.triangleAlert,
        label: _cashflowAnomalyReviewLabel,
        description: _cashflowAnomalyReviewDescription,
        userToggleable: false,
        visibleInSettings: false,
        placement: AgentResultPlacement.settingsOnly,
      ),
      AgentPresentationSpec(
        agentId: kFirePlanDriftMonitorAgentId,
        domain: DomainScope.finance,
        icon: FLucideIcons.flame,
        label: _firePlanDriftMonitorLabel,
        description: _firePlanDriftMonitorDescription,
        userToggleable: false,
        visibleInSettings: false,
        placement: AgentResultPlacement.settingsOnly,
      ),
      AgentPresentationSpec(
        agentId: kOptionsIncomeRiskReviewAgentId,
        domain: DomainScope.finance,
        icon: FLucideIcons.shieldAlert,
        label: _optionsIncomeRiskReviewLabel,
        description: _optionsIncomeRiskReviewDescription,
        userToggleable: false,
        visibleInSettings: false,
        placement: AgentResultPlacement.settingsOnly,
      ),
    ],
    memorySourcePrefixes: const ['fin:', kTradeJournalSource],
  ),
  shell: DomainShellContribution(
    navigation: const DomainNavigation(
      shellSpecBuilder: financeDomainShell,
      shellRouteBuilder: financeShellRoute,
      tabPaths: [
        AppRoutes.home,
        AppRoutes.activity,
        AppRoutes.wealth,
        AppRoutes.plan,
      ],
      additionalPathPrefixes: [AppRoutes.cashflow],
      deferredPreloader: preloadFinanceDeferredRoutesForTest,
    ),
    accent: DomainAccents.finance,
    commandPaletteEntriesBuilder: financeCommandPaletteEntries,
    settingsSpec: domainSettingsSpec(
      icon: FLucideIcons.walletCards,
      label: 'FinanceOS',
      subtitle: _financeSettingsSubtitle,
      alwaysEnabled: true,
      routePath: SettingsRoutes.domainsFinance,
      routeName: SettingsRouteNames.domainsFinance,
      page: const FinanceSettingsPage(),
    ),
    settingsRoutesBuilder: financeSettingsRoutes,
  ),
  lifecycle: const DomainLifecycleContribution(
    memoryBootstrapBuilder: _financeMemoryBootstrap,
    backgroundBootstrapBuilder: financeBackgroundBootstrap,
    providerOverridesBuilder: financeCompositionOverrides,
  ),
  data: DomainDataContribution(
    lifeSignalBuilder: financeLifeSignals,
    sourceRouteResolver: financeSourceRoute,
    localTableCountsBuilder: financeLocalTableCounts,
    dataManagementSpec: financeDataManagementSpec,
    shareIntentHandlers: const [FinanceShareIntentHandler()],
  ),
);

List<Agent> _financeAgents(Ref ref) =>
    ref.watch(finance_agent_providers.financeAgentsProvider);

void _financeMemoryBootstrap(Ref ref) {
  ref.watch(tradeJournalMemoryIndexerProvider);
}

String _financeSettingsSubtitle(AppLocalizations l10n, bool _) =>
    l10n.settingsDomainsFinanceSubtitle;

String _weeklyWealthReviewLabel(AppLocalizations l10n) =>
    l10n.agentPresentationWeeklyWealthReviewLabel;

String _weeklyWealthReviewDescription(AppLocalizations l10n) =>
    l10n.agentPresentationWeeklyWealthReviewDescription;

String _cashflowAnomalyReviewLabel(AppLocalizations l10n) =>
    l10n.agentPresentationCashflowAnomalyReviewLabel;

String _cashflowAnomalyReviewDescription(AppLocalizations l10n) =>
    l10n.agentPresentationCashflowAnomalyReviewDescription;

String _firePlanDriftMonitorLabel(AppLocalizations l10n) =>
    l10n.agentPresentationFirePlanDriftMonitorLabel;

String _firePlanDriftMonitorDescription(AppLocalizations l10n) =>
    l10n.agentPresentationFirePlanDriftMonitorDescription;

String _optionsIncomeRiskReviewLabel(AppLocalizations l10n) =>
    l10n.agentPresentationOptionsIncomeRiskReviewLabel;

String _optionsIncomeRiskReviewDescription(AppLocalizations l10n) =>
    l10n.agentPresentationOptionsIncomeRiskReviewDescription;
