import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../features/finance/composition/finance_bootstrap.dart';
import '../../features/finance/composition/finance_command_palette.dart';
import '../../features/finance/composition/finance_domain_shell.dart';
import '../../features/finance/composition/finance_intents.dart';
import '../../features/finance/composition/finance_proposal_applier.dart'
    as finance_proposals;
import '../../features/finance/composition/finance_proposal_kinds.dart'
    show kFinanceProposalKinds;
import '../../features/finance/composition/finance_routes.dart';
import '../../features/finance/data/diagnostics/local_table_counts.dart';
import '../../features/finance/options_income/data/trade_journal_memory_indexer.dart';
import '../../features/finance/ui/settings/finance_domain_settings_section.dart';
import '../../features/finance_ai_tools.dart';
import '../../l10n/gen/app_localizations.dart';
import '../route_paths.dart';
import 'proposal_applier_route.dart';

final DomainPack kFinancePack = DomainPack(
  scope: DomainScope.finance,
  deviceTools: kFinanceDeviceTools,
  toolDescriptors: kFinanceToolDescriptors,
  intentDescriptors: kFinanceIntentDescriptors,
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
  // recurring + dividends) but isn't a primary tab. It is surfaced through
  // Wealth / Plan navigation, but route ownership still belongs to Finance.
  additionalPathPrefixes: [AppRoutes.cashflow],
  memoryBootstrapBuilder: _financeMemoryBootstrap,
  backgroundBootstrapBuilder: financeBackgroundBootstrap,
  commandPaletteEntriesBuilder: financeCommandPaletteEntries,
  providerOverridesBuilder: financeCompositionOverrides,
  localTableCountsBuilder: financeLocalTableCounts,
  settingsSpec: const DomainSettingsSpec(
    icon: FLucideIcons.walletCards,
    label: 'FinanceOS',
    subtitle: _financeSettingsSubtitle,
    sectionBuilder: _financeSettingsSection,
  ),
);

void _financeMemoryBootstrap(Ref ref) {
  ref.watch(tradeJournalMemoryIndexerProvider);
}

String _financeSettingsSubtitle(AppLocalizations l10n, bool _) =>
    l10n.settingsDomainsFinanceSubtitle;

Widget _financeSettingsSection() => const FinanceDomainSettingsSection();
