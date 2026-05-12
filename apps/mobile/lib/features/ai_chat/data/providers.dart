import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/local/skills/skills.dart';
import '../../../core/ai/router/router.dart';
import '../../../core/ai/trace/trace.dart';
import '../../../core/auth/providers.dart';
import '../../../core/logging/providers.dart';
import '../../../core/sync/providers.dart';
import '../../../data/db/providers.dart';
import '../../../data/domain/asset.dart';
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

/// Dio dedicated to `/ai/*` endpoints. The receive timeout is large
/// because a single chat turn can sit on a streaming connection for
/// minutes (multi-tool loops + long Anthropic generations). We disable
/// the receive timeout entirely by setting it to a very long bound;
/// short of that, mid-stream the connection would be torn down even
/// though the worker is still emitting frames.
final aiChatDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );
  dio.interceptors.add(TalkerDioLogger(talker: ref.read(talkerProvider)));
  return dio;
});

final aiChatApiClientProvider = Provider<AiChatApiClient>(
  (ref) => DioAiChatApiClient(dio: ref.watch(aiChatDioProvider)),
);

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
    portfolioSnapshotReader: () => _buildPortfolioSnapshot(ref),
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
    final freshnessHint = pendingNames.isEmpty
        ? null
        : FreshnessHint(
            forceRefreshReadModels: pendingNames.toList(growable: false),
          );
    if (pendingNames.isNotEmpty) {
      ref.read(pendingFreshnessHintProvider.notifier).state = <String>{};
    }

    // Snapshot local HLC once: used by both the freshness gate
    // (tool_result watermark comparison) AND the analytical_uploads
    // device_hlc tag (§4.3.3).
    final localHlc = await ref.read(syncLocalHlcProvider.future);
    final localHlcText = localHlc?.toString();

    // Wave 11/15/16/17 — derive AnalyticalUpload list from end-side detector
    // outputs. anomaly_flag comes from expenseAnomalyInsightProvider
    // (Wave 11); recurring_pattern/refund_link/transfer_link from the
    // skills detectors over the expense stream (Wave 15/16);
    // investment_performance from holdingsSnapshotProvider (Wave 17).
    final expenses = await _readExpensesForRecurring(ref);
    final holdings = await _readHoldingsForPerformance(ref);
    final analyticalUploads = _buildAnalyticalUploads(
      anomaly: anomaly,
      expenses: expenses,
      holdings: holdings,
    );

    final pack = compressor.compress(
      route: route,
      intent: intent,
      baseCurrency: metrics?.baseCurrency,
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

    return (pack: pack, traceSeed: seed, localHlcText: localHlcText);
  } catch (_) {
    return (pack: null, traceSeed: null, localHlcText: null);
  }
}

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
  if (anomaly != null) {
    final now = DateTime.now().toUtc();
    final yearMonth = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final deltaPct = (anomaly.deltaRatio * 100).round();
    final severity = anomaly.deltaRatio.abs() > 0.5
        ? 'critical'
        : (anomaly.deltaRatio.abs() > 0.25 ? 'warn' : 'info');
    out.add(
      AnalyticalUpload(
        kind: 'anomaly_flag',
        id: 'expense_monthly_spike|$yearMonth',
        payload: <String, Object?>{
          'category': 'all_expense',
          'kind': 'monthly_spike',
          'delta_pct': deltaPct,
          'delta_ratio': anomaly.deltaRatio,
          'severity': severity,
          'detected_at': now.toIso8601String(),
        },
      ),
    );
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
        .map(_expenseToTransactionInput)
        .toList(growable: false);
    final patterns = detectRecurring(transactionInputs);
    for (final p in patterns) {
      out.add(_recurringPatternToUpload(p));
    }
    final refunds = matchRefunds(transactionInputs);
    for (final r in refunds) {
      out.add(_refundMatchToUpload(r));
    }
    final transfers = matchTransfers(transactionInputs);
    for (final t in transfers) {
      out.add(_transferMatchToUpload(t));
    }
  }

  // Wave 17: per-asset holding snapshot → investment_performance upload.
  for (final snap in holdings.values) {
    out.add(_holdingSnapshotToUpload(snap));
  }

  return out;
}

/// Map a domain Expense → a neutral TransactionInput the skill module
/// consumes. Expense.amount is the positive magnitude (per its docstring);
/// the detector wants signed minor units (negative = outflow), so we
/// negate here.
TransactionInput _expenseToTransactionInput(Expense e) {
  final cents = (e.amount * Decimal.fromInt(100)).floor().toBigInt();
  return TransactionInput(
    id: e.id,
    description: e.note ?? '',
    amountMinor: '-$cents',
    currency: e.currency,
    occurredAt: e.tradeDate,
    accountId: e.expenseAccountId,
    categoryId: e.expenseAccountId,
  );
}

AnalyticalUpload _recurringPatternToUpload(RecurringPattern p) {
  return AnalyticalUpload(
    kind: 'recurring_pattern',
    id: '${p.merchantKey}|${p.currency}',
    payload: <String, Object?>{
      'merchant_key': p.merchantKey,
      'cadence': p.cadence.name,
      'median_amount_minor': p.medianAmountMinor.toString(),
      'currency': p.currency,
      'occurrences': p.occurrenceIds.length,
      'last_seen_at': p.lastSeenAt.toIso8601String(),
    },
  );
}

AnalyticalUpload _refundMatchToUpload(RefundMatch m) {
  return AnalyticalUpload(
    kind: 'refund_link',
    id: '${m.originalTxnId}|${m.refundTxnId}',
    payload: <String, Object?>{
      'original_txn_id': m.originalTxnId,
      'refund_txn_id': m.refundTxnId,
      'amount_minor': m.amountMinor.toString(),
      'currency': m.currency,
    },
  );
}

AnalyticalUpload _transferMatchToUpload(TransferMatch m) {
  return AnalyticalUpload(
    kind: 'transfer_link',
    id: '${m.fromTxnId}|${m.toTxnId}',
    payload: <String, Object?>{
      'from_txn_id': m.fromTxnId,
      'to_txn_id': m.toTxnId,
      'amount_minor': m.amountMinor.toString(),
      'currency': m.currency,
    },
  );
}

AnalyticalUpload _holdingSnapshotToUpload(HoldingSnapshot snap) {
  return AnalyticalUpload(
    kind: 'investment_performance',
    id: snap.assetId,
    payload: <String, Object?>{
      'asset_id': snap.assetId,
      'asset_currency': snap.assetCurrency,
      'base_currency': snap.baseCurrency,
      'as_of': snap.asOf.toUtc().toIso8601String(),
      'quantity': snap.quantity.toString(),
      'cost_basis_in_asset_currency': snap.costBasisInAssetCurrency.toString(),
      'market_value_in_asset_currency':
          snap.marketValueInAssetCurrency.toString(),
      'cost_basis_in_base': snap.costBasisInBase.toString(),
      'market_value_in_base': snap.marketValueInBase.toString(),
      'unrealized_pnl_in_base': snap.unrealizedPnlInBase.toString(),
      'weight': snap.weight.toString(),
    },
  );
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

Future<Map<String, Object?>?> _buildPortfolioSnapshot(Ref ref) async {
  final holdings = await ref.read(holdingsSnapshotProvider.future);
  if (holdings.isEmpty) return null;
  final assets = await ref.read(allAssetsStreamProvider.future);
  final byId = {for (final asset in assets) asset.id: asset};
  final asOf = holdings.values.first.asOf.toUtc().toIso8601String();
  final baseCurrency = holdings.values.first.baseCurrency;
  return <String, Object?>{
    'as_of': asOf,
    'base_currency': baseCurrency,
    'holdings': <String, Object?>{
      for (final entry in holdings.entries)
        entry.key: _holdingSnapshotJson(entry.value, byId[entry.key]),
    },
  };
}

Map<String, Object?> _holdingSnapshotJson(HoldingSnapshot snap, Asset? asset) {
  return <String, Object?>{
    'asset_id': snap.assetId,
    'symbol': asset?.symbol,
    'name': asset?.name,
    'type': asset?.type.name,
    'net_quantity': snap.quantity.toString(),
    'asset_currency': snap.assetCurrency,
    'market_value_asset_currency': snap.marketValueInAssetCurrency.toString(),
    'cost_basis_asset_currency': snap.costBasisInAssetCurrency.toString(),
    'base_currency': snap.baseCurrency,
    'market_value_base': snap.marketValueInBase.toString(),
    'cost_basis_base': snap.costBasisInBase.toString(),
    'unrealized_pnl_base': snap.unrealizedPnlInBase.toString(),
    'weight': snap.weight.toString(),
    'as_of': snap.asOf.toUtc().toIso8601String(),
  };
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
  return ProposalApplier(
    tradeEntryService: tradeService,
    journalEntryRepo: journalEntryRepo,
    priceRepo: priceRepo,
    accountRepo: accountRepo,
    manualAssetRepo: manualAssetRepo,
    liabilityRepo: liabilityRepo,
    currentUserId: currentUserId,
  );
});
