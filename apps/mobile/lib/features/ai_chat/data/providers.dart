import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/composition/chat_trace_prep.dart';
import '../../../core/ai/composition/portfolio_snapshot.dart';
import '../../../core/ai/runtime/chat_agent.dart';
import '../../../core/ai/trace/trace.dart';
import '../../../core/auth/providers.dart';
import '../../../core/persistence/providers.dart';
import '../domain/chat_models.dart';
import 'ai_chat_api_client.dart';
import 'chat_history_store.dart';
import 'chat_repository.dart';
import 'runtime_routing_api_client.dart';

/// App-composed chat agent. Feature defaults stay unavailable so a partial
/// ProviderContainer cannot silently fall back to a legacy runtime.
final chatAgentProvider = Provider<ChatAgent?>((ref) => null);

/// What `ChatRepository` injects before app-level composition.
final aiChatApiClientProvider = Provider<AiChatApiClient>((ref) {
  return RuntimeRoutingAiChatApiClient(agent: ref.watch(chatAgentProvider));
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
  final tracePrep = ref.watch(chatTracePrepProvider);
  final portfolioReader = ref.watch(portfolioSnapshotReaderProvider);
  return ChatRepository(
    store: store,
    api: api,
    sessionReader: reader,
    portfolioSnapshotReader: portfolioReader,
    tracePrep: tracePrep,
    traceStore: traceStore,
  );
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
