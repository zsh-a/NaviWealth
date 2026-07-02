/// Bundle of every FinanceOS provider override plugged into LifeOS shell
/// composition seams (`docs/architecture/lifeos-shell.md` §4).
///
/// `kFinancePack` exposes [financeCompositionOverrides] through its
/// `providerOverridesBuilder`, keeping Finance-specific AI seams out of
/// `app/bootstrap.dart`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:flutter_riverpod/misc.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_providers.dart';

import '../../../core/ai/composition/ai_context_summary.dart';
import '../../../core/ai/composition/chat_rail_provider.dart';
import '../../../core/ai/composition/chat_trace_prep.dart';
import '../../../core/ai/composition/portfolio_snapshot.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/providers.dart' as auth;
import '../../../core/command_palette/local_query_result_pane_provider.dart';
import '../../home/composition/finance_chat_rail_provider.dart';
import '../ai_tools/drift_query_plan_executor.dart';
import '../command_palette/finance_ask_ai_result_pane.dart';
import '../command_palette/finance_query_plan_executor_provider.dart';
import '../data/market/sync/price_sync_providers.dart';
import 'finance_ai_context_summary_provider.dart';
import 'finance_chat_trace_preparer.dart';
import 'finance_portfolio_snapshot.dart';

/// Every FinanceOS shell-seam override in one place. Each entry maps a
/// `core/ai/composition/` provider to its Finance implementation; the
/// shell defaults (no-op applier, empty rail, etc.) stay live for
/// builds that don't include this list.
List<Override> financeCompositionOverrides() => [
  // Chat rail content selector lives in FinanceOS; the chat surface reads
  // only the seam, never the Finance provider directly.
  chatRailContentSelectorProvider.overrideWith(
    (ref) => ref.watch(financeChatRailContentSelectorProvider),
  ),
  // Per-chat-turn ContextPack + AiTrace seed; the chat repository skips
  // the trace seam when this is null.
  chatTracePrepProvider.overrideWith(
    (ref) => ref.watch(financeChatTracePrepProvider),
  ),
  // AI page header summary chip. Finance contributes net-worth / anomaly
  // / maturity facts; the default empty summary collapses.
  aiContextSummaryProvider.overrideWith(
    (ref) => ref.watch(financeAiContextSummaryProvider),
  ),
  // Portfolio snapshot attached to each chat turn for grounding.
  portfolioSnapshotReaderProvider.overrideWith(
    (ref) => ref.watch(financePortfolioSnapshotReaderProvider),
  ),
  financeQueryPlanExecutorProvider.overrideWith(
    (ref) => DriftQueryPlanExecutor(ref: ref),
  ),
  localQueryResultPaneBuilderProvider.overrideWith((ref) {
    final executor = ref.watch(financeQueryPlanExecutorProvider);
    return ({
      required String query,
      required DateTime now,
      void Function(String query)? onContinueInChat,
    }) => FinanceAskAiResultPane(
      query: query,
      executor: executor,
      now: now,
      onContinueInChat: onContinueInChat,
    );
  }),
  // NOTE: `proposalApplierProvider` and `proposalKindRegistryProvider` are
  // composed from active `DomainPack` entries in `app/domain_composition.dart`.
  // FinanceOS exposes `financeProposalApplierProvider` and proposal specs for
  // `kFinancePack` to read instead of overriding those seams here.
];

/// FinanceOS startup jobs owned by the Finance domain pack.
///
/// Price sync needs an active local or cloud session because it writes through
/// the finance repositories. Recurring materialisation remains local-first and
/// runs once on startup regardless of cloud auth, matching the previous app
/// bootstrap behaviour.
void financeBackgroundBootstrap(Ref ref) {
  final authState = ref.read(auth.authStateProvider);
  if (authState is AuthLoggedIn || authState is AuthLocalOnly) {
    ref.read(priceSyncCoordinatorBootstrapProvider);
  }
  unawaited(
    ref.read(recurringMaterialiseDueProvider(DateTime.now().toUtc()).future),
  );
}
