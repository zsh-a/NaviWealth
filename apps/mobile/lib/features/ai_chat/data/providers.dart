import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import '../../../core/logging/providers.dart';
import '../../../data/db/providers.dart';
import '../domain/chat_models.dart';
import 'ai_chat_api_client.dart';
import 'chat_history_store.dart';
import 'chat_repository.dart';

/// Dio dedicated to `/ai/*` endpoints. The receive timeout is large
/// because a single chat turn can sit on a streaming connection for
/// minutes (multi-tool loops + long Anthropic generations). We disable
/// the receive timeout entirely by setting it to a very long bound;
/// short of that, mid-stream the connection would be torn down even
/// though the worker is still emitting frames.
final aiChatDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  return Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );
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
