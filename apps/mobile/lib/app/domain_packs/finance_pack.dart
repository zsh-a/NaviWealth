import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/agents/agent_presentation.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/features/finance/agents/cashflow_anomaly_review_agent.dart'
    show kCashflowAnomalyReviewAgentId, kCashflowAnomalyReviewMemorySource;
import 'package:naviwealth/features/finance/agents/fire_plan_drift_monitor_agent.dart'
    show kFirePlanDriftMonitorAgentId, kFirePlanDriftMonitorMemorySource;
import 'package:naviwealth/features/finance/agents/options_income_risk_review_agent.dart'
    show kOptionsIncomeRiskReviewAgentId, kOptionsIncomeRiskReviewMemorySource;
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/agents/weekly_wealth_review_agent.dart'
    show kWeeklyWealthReviewAgentId, kWeeklyWealthReviewMemorySource;
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
import 'package:naviwealth/features/finance/ui/settings/finance_domain_settings_section.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../routing/route_paths.dart';
import 'proposal_applier_route.dart';

final DomainPack kFinancePack = DomainPack(
  scope: DomainScope.finance,
  deviceTools: kFinanceDeviceTools,
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
  // recurring) but isn't a primary tab. Dividends live under
  // `/wealth/portfolio/dividends`. Route ownership still belongs to Finance.
  additionalPathPrefixes: [AppRoutes.cashflow],
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
      placement: AgentResultPlacement.domainHome,
    ),
    AgentPresentationSpec(
      agentId: kFirePlanDriftMonitorAgentId,
      domain: DomainScope.finance,
      icon: FLucideIcons.flame,
      label: _firePlanDriftMonitorLabel,
      description: _firePlanDriftMonitorDescription,
      placement: AgentResultPlacement.domainHome,
    ),
    AgentPresentationSpec(
      agentId: kOptionsIncomeRiskReviewAgentId,
      domain: DomainScope.finance,
      icon: FLucideIcons.shieldAlert,
      label: _optionsIncomeRiskReviewLabel,
      description: _optionsIncomeRiskReviewDescription,
      placement: AgentResultPlacement.domainHome,
    ),
  ],
  memorySourcePrefixes: const [
    kTradeJournalSource,
    kWeeklyWealthReviewMemorySource,
    kCashflowAnomalyReviewMemorySource,
    kFirePlanDriftMonitorMemorySource,
    kOptionsIncomeRiskReviewMemorySource,
  ],
  memoryBootstrapBuilder: _financeMemoryBootstrap,
  backgroundBootstrapBuilder: financeBackgroundBootstrap,
  commandPaletteEntriesBuilder: financeCommandPaletteEntries,
  providerOverridesBuilder: financeCompositionOverrides,
  localTableCountsBuilder: financeLocalTableCounts,
  dataManagementSpec: financeDataManagementSpec,
  settingsRoutesBuilder: financeSettingsRoutes,
  shareIntentHandlers: const [FinanceShareIntentHandler()],
  settingsSpec: const DomainSettingsSpec(
    icon: FLucideIcons.walletCards,
    label: 'FinanceOS',
    subtitle: _financeSettingsSubtitle,
    sectionBuilder: _financeSettingsSection,
  ),
);

List<Agent> _financeAgents(Ref ref) =>
    ref.watch(finance_agent_providers.financeAgentsProvider);

void _financeMemoryBootstrap(Ref ref) {
  ref.watch(tradeJournalMemoryIndexerProvider);
}

String _financeSettingsSubtitle(AppLocalizations l10n, bool _) =>
    l10n.settingsDomainsFinanceSubtitle;

Widget _financeSettingsSection() => const FinanceDomainSettingsSection();

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
