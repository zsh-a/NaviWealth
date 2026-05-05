import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../../../core/auth/providers.dart';
import '../../../core/logging/providers.dart';
import '../../../core/sync/providers.dart';
import '../../../data/db/providers.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/mutation_context.dart';
import '../../../data/repositories/providers.dart';
import '../../investment/data/providers.dart';
import '../../liabilities/data/providers.dart';
import '../domain/chat_models.dart';
import '../state/chat_sync_gate.dart';
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
  dio.interceptors.add(
    TalkerDioLogger(talker: ref.read(talkerProvider)),
  );
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
  return ChatRepository(store: store, api: api, sessionReader: reader);
});

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
final chatSyncGateProvider = FutureProvider<ChatSyncGate>((ref) async {
  final engine = await ref.watch(syncEngineProvider.future);
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
  final manualAssetRepo = await ref.watch(
    manualAssetRepositoryProvider.future,
  );
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
