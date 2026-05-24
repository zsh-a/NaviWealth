import 'package:collection/collection.dart' show IterableExtension;
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/llm_credentials/llm_credentials.dart';
import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/ai/local/skills/skills.dart';
import '../../../core/ai/runtime/ai_runtime.dart';
import '../../../core/ai/runtime/device/anthropic/anthropic_client.dart';
import '../../../core/ai/runtime/device/openai/openai_client.dart';
import '../../../core/ai/runtime/device/tools/device_tool_registry.dart';
import '../../../core/ai/trace/trace.dart';
import '../../../core/ai/write/write.dart';
import '../../../core/auth/providers.dart';
import '../../../core/logging/providers.dart';
import '../../../core/sync/providers.dart';
import '../../../data/db/providers.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/expense.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/mutation_context.dart';
import '../../../data/repositories/providers.dart';
import '../../assets/data/deposit_maturity_insight_provider.dart';
import '../../expense/data/expense_anomaly_insight_provider.dart';
import '../../fire/data/fire_bucket_rules_preferences.dart';
import '../../fire/data/fire_providers.dart';
import '../../fire/domain/fire_bucket.dart';
import '../../fire/domain/fire_plan.dart';
import '../../fire/domain/fire_projection.dart' show FireScenarioTier;
import '../../home/data/dashboard_providers.dart';
import '../../investment/data/providers.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import '../../liabilities/data/providers.dart';
import '../../settings/data/risk_appetite_preferences.dart';
import '../domain/chat_models.dart';
import '../state/route_context_provider.dart';
import 'ai_chat_api_client.dart';
import 'chat_history_store.dart';
import 'chat_repository.dart';
import 'proposal_applier.dart';
import 'runtime_routing_api_client.dart';

/// §4.6 W-D3 — the on-device runtime, or `null` when unavailable (web /
/// no active profile). Rebuilt automatically when the active profile
/// changes, since [deviceLlmAvailableProvider] / [llmCredentialsProvider]
/// are watched. Each instance gets its own [Dio] because the base URL
/// is the user's (possibly custom) endpoint.
final deviceLlmRuntimeProvider = Provider<DeviceLlmRuntime?>((ref) {
  if (!ref.watch(deviceLlmAvailableProvider)) return null;
  final profile = ref.watch(llmCredentialsProvider).asData?.value?.active;
  if (profile == null || !profile.hasKey) return null;
  final dio = Dio()
    ..interceptors.add(TalkerDioLogger(talker: ref.read(talkerProvider)));
  final client = switch (profile.provider) {
    LlmProvider.anthropic => AnthropicClient(
      dio: dio,
      config: LlmConfig.fromProfile(profile),
    ),
    LlmProvider.openai => OpenAiClient(
      dio: dio,
      config: OpenAiConfig.fromProfile(profile),
    ),
  };
  // §4.6.3 — registry membership is the device allow-list. The
  // canonical set lives in `device_tool_registry.dart` (kDeviceTools)
  // so the W-D6 static-contract test shares one source. Tools not yet
  // ported simply aren't advertised, so the model never calls them.
  final registry = defaultDeviceToolRegistry();
  return DeviceLlmRuntime(
    client: client,
    dispatcher: DriftDeviceToolDispatcher(ref: ref, registry: registry),
    toolSchemas: registry.schemas(),
  );
});

/// §4.6 W-D7 — what `ChatRepository` injects. Device-only: every turn
/// runs on the on-device runtime; with no device (web / no key / opted
/// out) the turn surfaces an explanatory error (no cloud relay — the
/// `/ai/chat` backend was deleted in W-D7).
final aiChatApiClientProvider = Provider<AiChatApiClient>((ref) {
  return RuntimeRoutingAiChatApiClient(
    device: ref.watch(deviceLlmRuntimeProvider),
  );
});

/// Chat persistence is awaited once via [appDatabaseProvider]. We expose
/// the store as an `AsyncValue` so consumers can react to first-time DB
/// boot the same way the rest of the app does.
final chatHistoryStoreProvider = FutureProvider<ChatHistoryStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final store = ChatHistoryStore(db);
  ref.onDispose(store.dispose);
  return store;
});

final chatRepositoryProvider = FutureProvider<ChatRepository>((ref) async {
  final store = await ref.watch(chatHistoryStoreProvider.future);
  final api = ref.watch(aiChatApiClientProvider);
  final reader = ref.watch(authSessionReaderProvider);
  final traceStore = ref.watch(aiTraceStoreProvider);
  return ChatRepository(
    store: store,
    api: api,
    sessionReader: reader,
    portfolioSnapshotReader: () =>
        ref.read(devicePortfolioSnapshotProvider.future),
    tracePrep: ({required requestId}) => _prepareChatTrace(ref, requestId),
    traceStore: traceStore,
  );
});

/// Build the typed [ContextPack] + seed [AiTrace] for one chat turn.
///
/// Captures the current Riverpod state — route, header metrics, anomaly,
/// maturity — and folds it through [ContextCompressor]. Failures are
/// absorbed (returns nulls) so chat itself is never blocked by the
/// transparency layer hiccupping.
Future<ChatTracePrepResult> _prepareChatTrace(Ref ref, String requestId) async {
  try {
    final compressor = ref.read(contextCompressorProvider);
    final routeCtx = ref.read(aiRouteContextProvider);
    final route = RouteContext(
      path: routeCtx.path,
      area: _routeAreaFromPath(routeCtx.path),
    );
    // Phase 2-A: chat is `analyze × suggest` by default. Phase 3 will
    // classify per user message via NL→QueryPlan.
    const intent = IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.suggest,
      label: 'chat_turn',
    );

    final metricsAsync = ref.read(dashboardHeaderMetricsProvider);
    final metrics = metricsAsync.value;
    final anomaly = ref.read(expenseAnomalyInsightProvider);
    final maturity = ref.read(depositMaturityInsightProvider);

    // Snapshot local HLC once: stamps the `analytical_uploads` batch in
    // the ContextPack (device_hlc) so the LLM can reason about how
    // fresh the inlined detector summaries are.
    final localHlc = await ref.read(syncLocalHlcProvider.future);
    final localHlcText = localHlc?.toString();

    // Wave 11/15/16/17 — derive AnalyticalUpload list from end-side detector
    // outputs. anomaly_flag comes from expenseAnomalyInsightProvider
    // (Wave 11); recurring_pattern/refund_link/transfer_link from the
    // skills detectors over the expense stream (Wave 15/16);
    // investment_performance from holdingsSnapshotProvider (Wave 17).
    final expenses = await _readExpensesForRecurring(ref);
    final holdings = await _readHoldingsForPerformance(ref);
    final accountSummary = await _readAccountSummary(ref);
    final analyticalUploads = _buildAnalyticalUploads(
      anomaly: anomaly,
      expenses: expenses,
      holdings: holdings,
    );

    // Pull the user's declared risk appetite (Settings SSOT) and
    // project it onto the 3-value AI wire enum. The on-device LLM
    // sees the user's actual tolerance instead of the hardcoded
    // `moderate` placeholder the compressor used before W-D7's risk
    // appetite SSOT landed.
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
      analyticalUploads: analyticalUploads,
      deviceHlc: analyticalUploads.isEmpty ? null : localHlcText,
      riskPreference: riskAppetite.toWire(),
      fireGoal: fireGoal,
    );

    // Post-W-D7 there is only one runtime (device LLM) and one
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
          ? kDeviceLlmDirectRoutingReason
          : 'device_unavailable',
      usedCloud: false,
      totalDurationMs: 0,
    );

    return (
      pack: pack,
      traceSeed: effectiveSeed,
      traceVerbose: ref.read(aiTraceVerboseProvider),
    );
  } catch (_) {
    return (
      pack: null,
      traceSeed: null,
      traceVerbose: false,
    );
  }
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
      final scenario = view.scenarios.firstWhereOrNull(
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

/// One-shot read of the user's expenses for the recurring detector.
/// `journalExpensesStreamProvider` is autoDispose; calling `.future`
/// gets the first emission then unsubscribes. Returns `[]` on any
/// failure so chat is never blocked by analytics infra.
Future<List<Expense>> _readExpensesForRecurring(Ref ref) async {
  try {
    return await ref.read(journalExpensesStreamProvider.future);
  } catch (_) {
    return const <Expense>[];
  }
}

/// One-shot read of the per-asset HoldingSnapshot map for the Wave 17
/// `investment_performance` Analytical upload. Returns `{}` on any
/// failure — chat must not be blocked when the portfolio computer can't
/// converge (missing prices / fx rates / etc.).
Future<Map<String, HoldingSnapshot>> _readHoldingsForPerformance(
  Ref ref,
) async {
  try {
    return await ref.read(holdingsSnapshotProvider.future);
  } catch (_) {
    return const <String, HoldingSnapshot>{};
  }
}

/// Map end-side detector outputs into the wire-form
/// `AnalyticalUpload` list (§4.3.3).
///  - anomaly_flag: from `expenseAnomalyInsightProvider` (Wave 11)
///  - recurring_pattern: from `detectRecurring()` over the expense
///    stream (Wave 15) — converts Expense → TransactionInput then
///    runs the rules detector
///
/// Future waves add subscription_changes / investment_performance over
/// the same channel.
List<AnalyticalUpload> _buildAnalyticalUploads({
  ExpenseAnomalySummary? anomaly,
  List<Expense> expenses = const <Expense>[],
  Map<String, HoldingSnapshot> holdings = const <String, HoldingSnapshot>{},
}) {
  final out = <AnalyticalUpload>[];
  // §4.3.3 — single source shared with the device get_anomaly_flags
  // tool (W-D4.3) so cloud upload and device tool can't drift.
  final anomalyUpload = analyticalAnomalyUpload(anomaly);
  if (anomalyUpload != null) {
    out.add(anomalyUpload);
  }

  // Wave 15: run recurring_detector on expenses, convert each pattern.
  // Wave 16: run matchRefunds / matchTransfers over the same input set —
  // both detectors are pure functions of TransactionInput and produce
  // empty output when the input lacks the required pairing (refunds
  // need an inflow paired with an outflow; transfers need cross-account
  // flows). They will fire as the device feeds in more transaction
  // sources in later waves.
  // Empty list when there are no expenses / no detectable cadence.
  if (expenses.isNotEmpty) {
    final transactionInputs = expenses
        .map(expenseToTransactionInput)
        .toList(growable: false);
    final patterns = detectRecurring(transactionInputs);
    for (final p in patterns) {
      out.add(recurringPatternToUpload(p));
    }
    final refunds = matchRefunds(transactionInputs);
    for (final r in refunds) {
      out.add(refundMatchToUpload(r));
    }
    final transfers = matchTransfers(transactionInputs);
    for (final t in transfers) {
      out.add(transferMatchToUpload(t));
    }
    // Wave 19: subscription price changes (stateless detection over the
    // same input window).
    final subChanges = detectSubscriptionChanges(transactionInputs);
    for (final s in subChanges) {
      out.add(subscriptionChangeToUpload(s));
    }
  }

  // Wave 17: per-asset holding snapshot → investment_performance upload.
  for (final snap in holdings.values) {
    out.add(holdingSnapshotToUpload(snap));
  }

  return out;
}

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

/// Streamed list of all chat sessions for [ownerUserId]. Sidebar UI
/// watches this directly; one stream per user partition.
final chatSessionsStreamProvider =
    StreamProvider.family<List<ChatSession>, String>((ref, ownerUserId) async* {
      final repo = await ref.watch(chatRepositoryProvider.future);
      yield* repo.watchSessions(ownerUserId);
    });

/// Streamed message timeline for a single session. The chat page
/// watches this; updates fire after every SSE frame.
final chatMessagesStreamProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, sessionId) async* {
      final repo = await ref.watch(chatRepositoryProvider.future);
      yield* repo.watchMessages(sessionId);
    });

/// FIR-67 — applier that turns a confirmed `propose_*` plan into the
/// matching repository write. Pulled out as a Riverpod provider so
/// `ProposeCard` can resolve it once and pass it down to its action
/// handlers, without each card re-resolving every repository.
final proposalApplierProvider = FutureProvider<ProposalApplier>((ref) async {
  final tradeService = await ref.watch(tradeEntryServiceProvider.future);
  final journalEntryRepo = await ref.watch(
    journalEntryRepositoryProvider.future,
  );
  final priceRepo = await ref.watch(priceRepositoryProvider.future);
  final accountRepo = await ref.watch(accountRepositoryProvider.future);
  final manualAssetRepo = await ref.watch(manualAssetRepositoryProvider.future);
  final liabilityRepo = await ref.watch(liabilityRepositoryProvider.future);
  final currentUserId = ref.watch(currentUserIdProvider);
  // Wave 39 — optional touch store. May be null when the DB is mid-
  // boot or for unauthenticated sessions; the applier degrades to
  // its pre-Wave-39 behaviour (no source mark recorded) in that case.
  final touched = ref.watch(aiTouchedStoreProvider);
  return ProposalApplier(
    tradeEntryService: tradeService,
    journalEntryRepo: journalEntryRepo,
    priceRepo: priceRepo,
    accountRepo: accountRepo,
    manualAssetRepo: manualAssetRepo,
    liabilityRepo: liabilityRepo,
    currentUserId: currentUserId,
    aiTouchedStore: touched,
    // FIRE OS Phase 5 — confirm-and-apply for FIRE proposal kinds.
    firePlanWriter: (after) =>
        _applyFirePlanUpdateProposal(ref: ref, after: after),
    fireBucketRuleWriter: (payload) =>
        _applyFireBucketRuleProposal(ref: ref, payload: payload),
  );
});

Future<void> _applyFirePlanUpdateProposal({
  required Ref ref,
  required Map<String, Object?> after,
}) async {
  final plan = ref.read(firePlanProvider);
  Decimal? d(String key) {
    final raw = after[key];
    if (raw is num) return Decimal.parse(raw.toDouble().toStringAsFixed(2));
    if (raw is String) return Decimal.tryParse(raw);
    return null;
  }

  final updated = plan.copyWith(
    targetNetWorth: d('target_net_worth') ?? plan.targetNetWorth,
    monthlyExpenses: d('monthly_expenses') ?? plan.monthlyExpenses,
    monthlySurplus: d('monthly_surplus') ?? plan.monthlySurplus,
    inflationRate:
        (after['inflation_rate'] is num
                ? (after['inflation_rate'] as num).toDouble()
                : null) ??
            plan.inflationRate,
    safeWithdrawalRate:
        (after['safe_withdrawal_rate'] is num
                ? (after['safe_withdrawal_rate'] as num).toDouble()
                : null) ??
            plan.safeWithdrawalRate,
    targetCashBucketMonths:
        (after['target_cash_bucket_months'] is num
                ? (after['target_cash_bucket_months'] as num).toInt()
                : null) ??
            plan.targetCashBucketMonths,
    lifestyleMode: _parseLifestyle(after['lifestyle_mode']) ??
        plan.lifestyleMode,
  );
  await saveFirePlanWithRef(ref, updated);
}

FireLifestyleMode? _parseLifestyle(Object? raw) {
  if (raw is! String) return null;
  for (final m in FireLifestyleMode.values) {
    if (m.name == raw) return m;
  }
  return null;
}

Future<String> _applyFireBucketRuleProposal({
  required Ref ref,
  required Map<String, Object?> payload,
}) async {
  final roleRaw = payload['role'] as String? ?? '';
  final role = FireBucketRole.values.firstWhere(
    (r) => _wireForRole(r) == roleRaw,
    orElse: () => FireBucketRole.cash,
  );
  final targetId = payload['target_id'] as String? ?? '';
  if (targetId.isEmpty) {
    throw StateError('fire_bucket_rule payload missing target_id');
  }
  final pct = (payload['allocation_pct'] is num)
      ? (payload['allocation_pct'] as num).toDouble()
      : null;
  final note = payload['note'] as String?;
  final rule = FireBucketRule(
    id: targetId,
    role: role,
    targetTable: (payload['target_table'] as String?) ?? 'assets',
    targetId: targetId,
    allocationPct: pct,
    note: note,
  );
  await ref.read(fireBucketRulesProvider.notifier).upsert(rule);
  return targetId;
}

String _wireForRole(FireBucketRole role) {
  switch (role) {
    case FireBucketRole.cash:
      return 'cash';
    case FireBucketRole.defensive:
      return 'defensive';
    case FireBucketRole.growth:
      return 'growth';
    case FireBucketRole.riskReserve:
      return 'risk_reserve';
    case FireBucketRole.dream:
      return 'dream';
  }
}
