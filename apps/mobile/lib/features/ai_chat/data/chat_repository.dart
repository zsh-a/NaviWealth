import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/composition/chat_trace_prep.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/runtime/device/device_user_profile_prompt.dart';
import '../../../core/ai/trace/trace.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/auth/providers.dart';
import '../domain/chat_models.dart';
import '../domain/chat_turn_metadata.dart';
import 'ai_chat_api_client.dart';
import 'chat_history_store.dart';
import 'context_window.dart';

part 'chat_repository_message_mutations.dart';
part 'chat_repository_send.dart';
part 'chat_repository_sessions.dart';

/// Sentinel value for new session titles. UI layer should resolve to
/// localized string when displaying.
const kNewSessionTitle = '新对话';

/// Sentinel error message for cancelled requests. UI layer should
/// resolve to localized string when displaying.
const kCancelledError = '已取消';
const _userCancelledReason = 'user cancelled';

/// Outcome of a `sendMessage` turn — surfaced to the controller so the
/// UI can flip from "streaming" back to "idle" deterministically.
enum SendOutcome { completed, errored, cancelled }

/// Combines the chat HTTP client with persistence. Owns the message
/// timeline for one session: writes the user turn synchronously, then
/// drives the SSE stream into the assistant turn row, updating it
/// in-place as `text` / `tool_call` / `tool_result` frames arrive.
class ChatRepository
    with
        _ChatRepositorySessions,
        _ChatRepositoryMessageMutations,
        _ChatRepositorySend {
  ChatRepository({
    required ChatHistoryStore store,
    required AiChatApiClient api,
    required AuthSessionReader sessionReader,
    Future<Map<String, Object?>?> Function()? portfolioSnapshotReader,
    ChatTracePrep? tracePrep,
    AiTraceStore? traceStore,
    void Function(AiTrace finalized)? onTraceFinalized,
    Uuid? uuid,
  }) : _store = store,
       _api = api,
       _sessionReader = sessionReader,
       _portfolioSnapshotReader = portfolioSnapshotReader,
       _tracePrep = tracePrep,
       _traceStore = traceStore,
       _onTraceFinalized = onTraceFinalized,
       _uuid = uuid ?? const Uuid();

  @override
  final ChatHistoryStore _store;
  @override
  final AiChatApiClient _api;
  @override
  final AuthSessionReader _sessionReader;
  @override
  final Future<Map<String, Object?>?> Function()? _portfolioSnapshotReader;
  @override
  final ChatTracePrep? _tracePrep;
  @override
  final AiTraceStore? _traceStore;
  @override
  final void Function(AiTrace finalized)? _onTraceFinalized;
  @override
  final Uuid _uuid;

  Stream<List<ChatSession>> watchSessions(String ownerUserId) =>
      _store.watchSessions(ownerUserId);

  Stream<List<ChatMessage>> watchMessages(String sessionId) =>
      _store.watchMessages(sessionId);

  /// One-shot read of the user's existing sessions. Used by the AI chat
  /// page bootstrap so it never has to wait on a `StreamProvider.future`
  /// that may not deliver its first emission until the next change
  /// notification fires (an issue we hit with the page getting stuck on
  /// "Preparing conversation…" until the user manually tapped "+").
  Future<List<ChatSession>> listSessions(String ownerUserId) =>
      _store.listSessions(ownerUserId);

  Future<ChatSession?> findSession(String id) => _store.findSession(id);

  Future<void> renameSession(String id, String title) =>
      _store.renameSession(id, title);

  Future<void> setSessionPinned(String id, {required bool pinned}) =>
      _store.setSessionPinned(id, pinned: pinned);

  Future<void> setSessionArchived(String id, {required bool archived}) =>
      _store.setSessionArchived(id, archived: archived);

  Future<void> deleteSession(String id) => _store.deleteSession(id);

  /// Generates the context-truncation notice text. Callers in the UI layer
  /// may prefer `AppLocalizations.chatContextTruncated(count)` for proper
  /// i18n; this static is provided for data-layer callers that lack
  /// BuildContext.
  static String contextTruncatedNotice(int count) =>
      '已折叠 $count 条更早的历史以控制上下文长度。';
}
