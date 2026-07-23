import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/composition/chat_trace_prep.dart';
import '../../../core/ai/composition/portfolio_snapshot.dart';
import '../../../core/ai/runtime/chat_agent.dart';
import '../../../core/ai/trace/trace.dart';
import '../../../core/auth/providers.dart';
import '../../../core/persistence/providers.dart';
import '../domain/chat_models.dart';
import 'ai_chat_api_client.dart';
import 'chat_context_block_prep.dart';
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

/// App-level per-turn context assembly. The feature default is intentionally
/// absent so isolated tests and partial provider graphs do not pull domain
/// memories without an explicit composition policy.
final chatContextBlockPrepProvider = Provider<ChatContextBlockPrep?>(
  (ref) => null,
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
  final tracePrep = ref.watch(chatTracePrepProvider);
  final portfolioReader = ref.watch(portfolioSnapshotReaderProvider);
  final contextBlockPrep = ref.watch(chatContextBlockPrepProvider);
  return ChatRepository(
    store: store,
    api: api,
    sessionReader: reader,
    portfolioSnapshotReader: portfolioReader,
    contextBlockPrep: contextBlockPrep,
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

/// Structural timeline slots (id / role / status / day). Content is
/// intentionally omitted so streaming token updates do not rebuild the
/// list host — only appends / status flips do.
final chatTimelineStructureProvider =
    Provider.family<AsyncValue<List<ChatTimelineSlot>>, String>((
      ref,
      sessionId,
    ) {
      // Fingerprint omits content so token deltas leave the host alone.
      final fingerprint = ref.watch(
        chatMessagesStreamProvider(sessionId).select((async) {
          return async.when(
            data: (messages) =>
                'd:${messages.map((m) => '${m.id}:${m.role.index}:${m.status.index}:${m.createdAt.millisecondsSinceEpoch}').join('|')}',
            loading: () => 'l',
            error: (error, _) => 'e:$error',
          );
        }),
      );
      if (fingerprint == 'l') {
        return const AsyncLoading<List<ChatTimelineSlot>>();
      }
      final source = ref.read(chatMessagesStreamProvider(sessionId));
      if (fingerprint.startsWith('e:')) {
        return AsyncError<List<ChatTimelineSlot>>(
          source.error ?? StateError(fingerprint),
          source.stackTrace ?? StackTrace.current,
        );
      }
      final messages = source.asData?.value ?? const <ChatMessage>[];
      return AsyncData<List<ChatTimelineSlot>>([
        for (final message in messages)
          ChatTimelineSlot(
            id: message.id,
            role: message.role,
            status: message.status,
            createdAt: message.createdAt,
          ),
      ]);
    });

/// Single message by id. [select] compares via [ChatMessageVersion] so
/// streaming tokens only rebuild the in-flight bubble.
final chatMessageByIdProvider =
    Provider.family<ChatMessage?, ({String sessionId, String messageId})>((
      ref,
      key,
    ) {
      // Version gate: rebuild only when this message's render-relevant
      // fields change. Returning the full [ChatMessage] without a custom
      // select would rebuild every bubble on every token.
      final version = ref.watch(
        chatMessagesStreamProvider(key.sessionId).select((async) {
          final messages = async.asData?.value;
          if (messages == null) return null;
          for (final message in messages) {
            if (message.id == key.messageId) {
              return ChatMessageVersion.from(message);
            }
          }
          return null;
        }),
      );
      if (version == null) return null;
      final messages = ref
          .read(chatMessagesStreamProvider(key.sessionId))
          .asData
          ?.value;
      if (messages == null) return null;
      for (final message in messages) {
        if (message.id == key.messageId) return message;
      }
      return null;
    });

/// One row identity in the conversation list (no content payload).
@immutable
class ChatTimelineSlot {
  const ChatTimelineSlot({
    required this.id,
    required this.role,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final ChatRole role;
  final ChatMessageStatus status;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is ChatTimelineSlot &&
      other.id == id &&
      other.role == role &&
      other.status == status &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, role, status, createdAt);
}

/// Cheap structural fingerprint of a [ChatMessage] for Riverpod [select].
@immutable
class ChatMessageVersion {
  const ChatMessageVersion._(this._key);

  factory ChatMessageVersion.from(ChatMessage message) {
    final tools = message.toolCalls
        .map(
          (t) =>
              '${t.id}:${t.status.index}:${t.partialInputJson ?? ''}:'
              '${identityHashCode(t.output)}:${t.applyState?.status.name ?? ''}',
        )
        .join(',');
    final progress = message.progress;
    final progressKey = progress == null
        ? ''
        : '${progress.id}:${progress.label}:${progress.detail}:'
              '${progress.ratio}';
    return ChatMessageVersion._(
      '${message.id}|${message.content}|${message.status.index}|'
      '${message.reasoningText ?? ''}|${message.errorMessage ?? ''}|'
      '${message.stopReason?.index ?? -1}|${message.textSegments.join('\u001e')}|'
      '$tools|$progressKey',
    );
  }

  final String _key;

  @override
  bool operator ==(Object other) =>
      other is ChatMessageVersion && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}
