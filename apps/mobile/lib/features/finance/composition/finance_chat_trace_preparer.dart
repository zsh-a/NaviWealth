/// FinanceOS implementation of the chat trace preparer seam
/// (`docs/architecture/lifeos-shell.md` §4, D-1.6b).
///
/// Builds the per-chat-turn [ContextPack] + seed [AiTrace] from Finance
/// signals (header metrics, expense anomaly, deposit maturity, FIRE
/// goal, account summary, risk appetite). Registered in `bootstrap.dart`
/// as an override of `chatTracePrepProvider`.
library;

import 'package:collection/collection.dart' show IterableExtension;
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/preferences/risk_appetite_preferences.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../core/ai/composition/chat_trace_prep.dart';
import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/ai/local/skills/skills.dart';
import '../../../core/ai/trace/trace.dart';
import '../../ai_chat/state/ai_context.dart';
import '../../assets/data/deposit_maturity_insight_provider.dart';
import '../../expense/data/expense_anomaly_insight_provider.dart';
import '../../fire/data/fire_providers.dart';
import '../../fire/domain/fire_projection.dart' show FireScenarioTier;
import '../../home/data/dashboard_providers.dart';
import '../ai_tools/query_plan/finance_query_plan.dart';
import '../ai_tools/query_plan/nl_to_query_plan.dart';

/// Finance-domain trace-prep closure. Watches all the dashboard
/// providers + FIRE plan + risk appetite + account summary that the
/// model expects at chat-turn build time, and returns the typed
/// [ContextPack] + seed [AiTrace] for the repository to finalise.
final financeChatTracePrepProvider = Provider<ChatTracePrep>((ref) {
  return ({required String requestId, required String userMessage}) =>
      _prepareChatTrace(ref, requestId, userMessage);
});

/// Build the typed [ContextPack] + seed [AiTrace] for one chat turn.
///
/// Captures the current Riverpod state — route, header metrics, anomaly,
/// maturity — and folds it through [ContextCompressor]. Failures are
/// absorbed (returns nulls) so chat itself is never blocked by the
/// transparency layer hiccupping.
Future<ChatTracePrepResult> _prepareChatTrace(
  Ref ref,
  String requestId,
  String userMessage,
) async {
  try {
    final compressor = ref.read(contextCompressorProvider);
    final routeCtx = ref.read(aiContextProvider);
    final route = RouteContext(
      path: routeCtx.path,
      area: _routeAreaFromPath(routeCtx.path),
    );
    final intent = _intentForUserMessage(userMessage);

    final metricsAsync = ref.read(dashboardHeaderMetricsProvider);
    final metrics = metricsAsync.value;
    final anomaly = ref.read(expenseAnomalyInsightProvider);
    final maturity = ref.read(depositMaturityInsightProvider);
    final accountSummary = await _readAccountSummary(ref);

    // Pull the user's declared risk appetite (Settings SSOT) and
    // project it onto the 3-value AI wire enum.
    final riskAppetite = ref.read(riskAppetiteProvider);

    final fireGoal = _summarizeFireGoal(ref);

    final pack = compressor.compress(
      route: route,
      intent: intent,
      baseCurrency: metrics?.baseCurrency,
      accountSummary: accountSummary,
      expenseAnomalyDelta: anomaly?.deltaRatio,
      depositMaturityCount: maturity?.count,
      depositMaturityDays: maturity?.days,
      riskPreference: riskAppetite.toWire(),
      fireGoal: fireGoal,
    );

    // There is only one runtime (device LLM) and one
    // fallback (device_unavailable). The router that historically chose
    // between cloud / hybrid / device is gone; we stamp the trace
    // directly with the runtime that will actually run this turn.
    final deviceUsable = ref.read(deviceLlmAvailableProvider);
    final effectiveSeed = AiTrace(
      requestId: requestId,
      startedAtIso: DateTime.now().toUtc().toIso8601String(),
      intent: intent,
      backend: Backend.device,
      budgetTier: pack.budget.tier,
      routingReason: deviceUsable
          ? kFrbChatRoutingReason
          : kDeviceUnavailableRoutingReason,
      totalDurationMs: 0,
    );

    return (
      pack: pack,
      traceSeed: effectiveSeed,
      traceVerbose: ref.read(aiTraceVerboseProvider),
    );
  } catch (_) {
    return (pack: null, traceSeed: null, traceVerbose: false);
  }
}

IntentHint _intentForUserMessage(String message) {
  final plan = parseNlQuery(message, now: DateTime.now().toUtc());
  return switch (plan) {
    SpendingByCategoryPlan() => const IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.info,
      label: 'finance_spending_query',
    ),
    TransactionsFilterPlan() => const IntentHint(
      capability: Capability.search,
      risk: RiskLevel.info,
      label: 'finance_transaction_query',
    ),
    NetWorthTrendPlan() => const IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.info,
      label: 'finance_net_worth_trend_query',
    ),
    SubscriptionListPlan() => const IntentHint(
      capability: Capability.search,
      risk: RiskLevel.info,
      label: 'finance_subscription_query',
    ),
    RefundMatchingPlan() => const IntentHint(
      capability: Capability.search,
      risk: RiskLevel.info,
      label: 'finance_refund_query',
    ),
    null => const IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.suggest,
      label: 'chat_turn',
    ),
  };
}

/// Build a [FireGoalSummary] from the live `firePlanProvider` +
/// dashboard snapshot + projection scenarios. Returns `null` when the
/// plan has no configured target — that's a meaningful signal to the
/// AI ("ask the user about FIRE setup") rather than padding with zero.
///
/// All upstream reads are non-blocking `.value` lookups: a missing
/// snapshot or scenario simply degrades the summary (no progress, no
/// years estimate) but never blocks the chat turn.
FireGoalSummary? _summarizeFireGoal(Ref ref) {
  try {
    final plan = ref.read(firePlanProvider);
    if (plan.targetNetWorth <= Decimal.zero) return null;

    final snapshot = ref.read(dashboardSnapshotProvider).value;
    double progress = 0;
    if (snapshot != null && snapshot.netWorth.amount > Decimal.zero) {
      final ratio = (snapshot.netWorth.amount / plan.targetNetWorth).toDouble();
      progress = ratio.clamp(0.0, 1.0);
    }

    double? yearsRemaining;
    final view = ref.read(fireDashboardViewProvider).value;
    if (view != null && view.scenarios.isNotEmpty) {
      // Prefer the live / neutral scenario over an outlier — matches
      // the heuristic the FIRE state provider uses elsewhere.
      final scenario =
          view.scenarios.firstWhereOrNull(
            (s) => s.tier == FireScenarioTier.live,
          ) ??
          view.scenarios.firstWhereOrNull(
            (s) => s.tier == FireScenarioTier.neutral,
          ) ??
          view.scenarios.first;
      final months = scenario.monthsToTarget;
      if (months != null && months > 0) yearsRemaining = months / 12.0;
    }

    // The wire field is "minor units"; multiply by 100 so e.g. ¥1.5M
    // arrives as "150000000". The AI prompt only uses it qualitatively
    // (order-of-magnitude) — exact JPY/USD precision isn't needed.
    final targetMinor = (plan.targetNetWorth * Decimal.fromInt(100))
        .toBigInt()
        .toString();
    return FireGoalSummary(
      targetMinor: targetMinor,
      currency: plan.baseCurrency,
      progressFraction: progress,
      yearsRemainingEstimate: yearsRemaining,
    );
  } catch (_) {
    // Transparency wiring is best-effort; never block chat over it.
    return null;
  }
}

Future<AccountSummary> _readAccountSummary(Ref ref) async {
  try {
    final repo = await ref.read(accountRepositoryProvider.future);
    final accounts = await repo.listActive();
    final byKind = <String, int>{};
    for (final account in accounts) {
      final kind = _accountSummaryKind(account);
      byKind[kind] = (byKind[kind] ?? 0) + 1;
    }
    return AccountSummary(
      totalCount: accounts.length,
      byKind: Map<String, int>.unmodifiable(byKind),
    );
  } catch (_) {
    return const AccountSummary(totalCount: 0, byKind: <String, int>{});
  }
}

String _accountSummaryKind(Account account) => switch (account.type) {
  AccountCategory.cash => 'cash',
  AccountCategory.bank => 'bank',
  AccountCategory.broker => 'broker',
  AccountCategory.crypto => 'crypto',
  AccountCategory.credit => 'credit',
  AccountCategory.loan => 'loan',
  AccountCategory.asset => 'asset',
  AccountCategory.liability => 'liability',
};

String _routeAreaFromPath(String path) {
  if (path.startsWith('/expense')) return 'expense';
  if (path.startsWith('/investment') || path.startsWith('/portfolio')) {
    return 'investment';
  }
  if (path.startsWith('/fire')) return 'fire';
  if (path.startsWith('/account')) return 'account';
  if (path.startsWith('/liabilit')) return 'liability';
  if (path.startsWith('/asset')) return 'asset';
  if (path.startsWith('/settings')) return 'settings';
  if (path == '/' || path.startsWith('/home')) return 'home';
  return 'unknown';
}
