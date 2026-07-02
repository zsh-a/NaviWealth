import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/composition/composite_proposal_applier.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../features/finance/composition/finance_bootstrap.dart';
import '../../features/finance/composition/finance_command_palette.dart';
import '../../features/finance/composition/finance_intents.dart';
import '../../features/finance/composition/finance_proposal_applier.dart'
    as finance_proposals;
import '../../features/finance/composition/finance_proposal_kinds.dart'
    show kFinanceProposalKinds;
import '../../features/finance/composition/finance_routes.dart';
import '../../features/finance_ai_tools.dart';
import '../../features/finance_domain_shell.dart';
import '../../features/options_income/data/trade_journal_memory_indexer.dart';
import '../route_paths.dart';

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
  // recurring + dividends) but isn't a primary tab. It is surfaced through
  // Wealth / Plan navigation, but route ownership still belongs to Finance.
  additionalPathPrefixes: [AppRoutes.cashflow],
  memoryBootstrapBuilder: _financeMemoryBootstrap,
  backgroundBootstrapBuilder: financeBackgroundBootstrap,
  commandPaletteEntriesBuilder: financeCommandPaletteEntries,
  providerOverridesBuilder: financeCompositionOverrides,
);

void _financeMemoryBootstrap(Ref ref) {
  ref.watch(tradeJournalMemoryIndexerProvider);
}

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
