import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/ai/local/skills/skills.dart';
import '../../../core/ai/router/router.dart';
import '../../../core/ai/runtime/ai_runtime.dart';
import '../../../core/ai/runtime/device/anthropic/anthropic_client.dart';
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
import '../../home/data/dashboard_providers.dart';
import '../../investment/data/providers.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import '../../liabilities/data/providers.dart';
import '../domain/chat_models.dart';
import '../state/chat_sync_gate.dart';
import '../state/route_context_provider.dart';
import 'ai_chat_api_client.dart';
import 'chat_history_store.dart';
import 'chat_repository.dart';
import 'proposal_applier.dart';
import 'runtime_routing_api_client.dart';

/// §4.6 W-D3 — the on-device runtime, or `null` when unavailable (web /
/// no key / opted out). Rebuilt automatically when credentials or the
/// opt-in switch change, since [deviceLlmAvailableProvider] /
/// [llmCredentialsProvider] are watched. Each instance gets its own
/// [Dio] because the base URL is the user's (possibly custom) endpoint.
final deviceLlmRuntimeProvider = Provider<DeviceLlmRuntime?>((ref) {
  if (!ref.watch(deviceLlmAvailableProvider)) return null;
  final creds = ref.watch(llmCredentialsProvider).asData?.value;
  if (creds == null || !creds.isUsable) return null;
  final dio = Dio()
    ..interceptors.add(TalkerDioLogger(talker: ref.read(talkerProvider)));
  // §4.6.3 — registry membership is the device allow-list. The
  // canonical set lives in `device_tool_registry.dart` (kDeviceTools)
  // so the W-D6 static-contract test shares one source. Tools not yet
  // ported simply aren't advertised, so the model never calls them.
  final registry = defaultDeviceToolRegistry();
  return DeviceLlmRuntime(
    client: AnthropicClient(dio: dio, config: LlmConfig.fromCredentials(creds)),
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

/// AiRuntime registry. Post-W-D7 the `cloud_anthropic` runtime is gone
/// (cloud backend deleted); the map holds the stub `rules_device` and —
/// when available — the §4.6 `device_llm` runtime. `ChatRepository`
/// routes via [aiChatApiClientProvider]; the registry stays the
/// canonical id→runtime map for trace labelling.
final runtimeRegistryProvider = Provider<RuntimeRegistry>((ref) {
  final device = ref.watch(deviceLlmRuntimeProvider);
  return RuntimeRegistry(<RuntimeId, AiRuntime>{
    RuntimeId.rulesDevice: const RulesDeviceRuntime(),
    RuntimeId.deviceLlm: ?device,
  });
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
    onTraceFinalized: (trace) {
      // Phase 2 freshness gate bridge: collect read_model names that
      // were stale during this turn so the next chat send tells the
      // cloud to force-refresh them before dispatching.
      if (trace.staleReadModelNames.isEmpty) return;
      final pending = ref.read(pendingFreshnessHintProvider);
      ref.read(pendingFreshnessHintProvider.notifier).state = <String>{
        ...pending,
        ...trace.staleReadModelNames,
      };
    },
  );
});

/// Read model names whose `source_hlc_watermark` lagged the device's
/// local HLC on the last completed chat turn. Consumed (and cleared)
/// by `_prepareChatTrace` on the next request, injected into the
/// outgoing `ContextPack.task.freshnessHint.forceRefreshReadModels`.
///
/// docs/ai-architecture.md §4.2 (freshness gate Phase 2).
final pendingFreshnessHintProvider = StateProvider<Set<String>>(
  (_) => <String>{},
);

/// Build the typed [ContextPack] + seed [AiTrace] for one chat turn.
///
/// Captures the current Riverpod state — route, header metrics, anomaly,
/// maturity — and folds it through [ContextCompressor] and [AiRouter].
/// Failures are absorbed (returns nulls) so chat itself is never blocked
/// by the transparency layer hiccupping.
Future<ChatTracePrepResult> _prepareChatTrace(Ref ref, String requestId) async {
  try {
    final compressor = ref.read(contextCompressorProvider);
    final router = ref.read(aiRouterProvider);
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

    // Consume any pending freshness hint from the previous turn's
    // stale-read-model detection (Phase 2 gate). Clear immediately so
    // a second concurrent send doesn't double-trigger.
    final pendingNames = ref.read(pendingFreshnessHintProvider);
    if (pendingNames.isNotEmpty) {
      ref.read(pendingFreshnessHintProvider.notifier).state = <String>{};
    }

    // Snapshot local HLC once: used by both the freshness gate
    // (tool_result watermark comparison) AND the analytical_uploads
    // device_hlc tag (§4.3.3).
    final localHlc = await ref.read(syncLocalHlcProvider.future);
    final localHlcText = localHlc?.toString();

    // Wave 32: FreshnessHint now also carries lastLocalHlc so the
    // freshness protocol is self-contained. Always emit when either
    // the force-refresh list is non-empty OR we know the local HLC,
    // so the cloud has a freshness watermark even on no-op turns.
    final freshnessHint = (pendingNames.isEmpty && localHlcText == null)
        ? null
        : FreshnessHint(
            forceRefreshReadModels: pendingNames.toList(growable: false),
            lastLocalHlc: localHlcText,
          );

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

    final pack = compressor.compress(
      route: route,
      intent: intent,
      baseCurrency: metrics?.baseCurrency,
      accountSummary: accountSummary,
      expenseAnomalyDelta: anomaly?.deltaRatio,
      depositMaturityCount: maturity?.count,
      depositMaturityDays: maturity?.days,
      freshnessHint: freshnessHint,
      analyticalUploads: analyticalUploads,
      deviceHlc: analyticalUploads.isEmpty ? null : localHlcText,
    );

    // The chat surface is by definition online here (we are about to
    // POST to /ai/chat) so the router decides cloud-bound. We capture
    // the decision regardless so AiTrace records why.
    final decision = router.decide(
      const RoutingInputs(intent: intent, online: true),
    );
    final seed = router.seedTrace(requestId: requestId, decision: decision);

    // §4.6 W-D6 — keep the transparency record truthful: the router
    // always decides cloud for an online chat, but if the on-device
    // runtime will actually handle this turn (native × key × opt-in),
    // the trace must say so. `device_llm_direct` also drives the
    // distinct "未经我方服务器" badge text.
    final effectiveSeed = ref.read(deviceLlmAvailableProvider)
        ? seed.copyWith(
            backend: Backend.device,
            routingReason: kDeviceLlmDirectRoutingReason,
            usedCloud: false,
          )
        : seed;

    return (pack: pack, traceSeed: effectiveSeed, localHlcText: localHlcText);
  } catch (_) {
    return (pack: null, traceSeed: null, localHlcText: null);
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

/// Pre-chat sync flush gate (FIR-71). The AI backend reads the user's
/// data from D1, which is updated by the client's OpLog push. Without
/// this gate, a user who records a transaction and immediately asks the
/// model "what's my position?" can race the 30-s polling cycle and get
/// a stale answer.
final chatSyncGateProvider = FutureProvider<ChatSyncGate?>((ref) async {
  final engine = await ref.watch(syncEngineProvider.future);
  if (engine == null) return null;
  return ChatSyncGate(engine: engine);
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
  );
});
