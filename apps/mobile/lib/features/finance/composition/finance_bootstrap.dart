/// Bundle of every FinanceOS provider override the root
/// `bootstrap.dart` plugs into the shell composition seams
/// (`docs/lifeos-shell.md` §4).
///
/// Bootstrap spreads [financeCompositionOverrides] into its `overrides`
/// list — one line in the composition root rather than six. New domain
/// composition (HealthOS, KnowledgeOS, …) follows the same pattern:
/// `features/<domain>/composition/<domain>_bootstrap.dart` returns its
/// own `List<Override>` and `bootstrap.dart` spreads each domain's
/// bundle in turn.
library;

import 'package:flutter_riverpod/misc.dart';

import '../../../core/ai/composition/ai_context_summary.dart';
import '../../../core/ai/composition/chat_rail_provider.dart';
import '../../../core/ai/composition/chat_trace_prep.dart';
import '../../../core/ai/composition/portfolio_snapshot.dart';
import '../../home/composition/finance_chat_rail_provider.dart';
import 'finance_ai_context_summary_provider.dart';
import 'finance_chat_trace_preparer.dart';
import 'finance_portfolio_snapshot.dart';

/// Every FinanceOS shell-seam override in one place. Each entry maps a
/// `core/ai/composition/` provider to its Finance implementation; the
/// shell defaults (no-op applier, empty rail, etc.) stay live for
/// builds that don't include this list.
List<Override> financeCompositionOverrides() => [
  // D-1.6: chat rail content selector lives in FinanceOS — the chat
  // surface in `features/ai_chat/` reads only the seam, never the
  // Finance provider directly.
  chatRailContentSelectorProvider.overrideWith(
    (ref) => ref.watch(financeChatRailContentSelectorProvider),
  ),
  // D-1.6b: per-chat-turn ContextPack + AiTrace seed; the chat
  // repository skips the trace seam when this is null.
  chatTracePrepProvider.overrideWith(
    (ref) => ref.watch(financeChatTracePrepProvider),
  ),
  // D-1.6b: AI page header summary chip — Finance contributes
  // net-worth / anomaly / maturity facts; default empty collapses.
  aiContextSummaryProvider.overrideWith(
    (ref) => ref.watch(financeAiContextSummaryProvider),
  ),
  // D-1.6b: portfolio snapshot attached to each chat turn for grounding.
  portfolioSnapshotReaderProvider.overrideWith(
    (ref) => ref.watch(financePortfolioSnapshotReaderProvider),
  ),
  // NOTE: `proposalApplierProvider` + `proposalKindRegistryProvider` are
  // composed across domains in `knowledge_bootstrap.dart`
  // (`docs/knowledgeos-domain.md` §15.6) — Riverpod 3 throws on a
  // double-override, so the cross-domain composite owns these two seams.
  // FinanceOS still exposes `financeProposalApplierProvider` +
  // `kFinanceProposalKinds` as plain providers for that composite to read.
];
