import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  );
});

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

    final pack = compressor.compress(
      route: route,
      intent: intent,
      baseCurrency: metrics?.baseCurrency,
      expenseAnomalyDelta: anomaly?.deltaRatio,
      depositMaturityCount: maturity?.count,
      depositMaturityDays: maturity?.days,
    );

    // The chat surface is by definition online here (we are about to
    // POST to /ai/chat) so the router decides cloud-bound. We capture
    // the decision regardless so AiTrace records why.
    final decision = router.decide(
      const RoutingInputs(intent: intent, online: true),
    );
    final seed = router.seedTrace(requestId: requestId, decision: decision);

    return (pack: pack, traceSeed: seed);
  } catch (_) {
    return (pack: null, traceSeed: null);
  }
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
