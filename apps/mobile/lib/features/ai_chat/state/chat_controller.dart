import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/interaction/interaction_chat_session.dart';
import '../../../core/ai/session/interaction_state.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/providers.dart';
import '../../../core/speech/speech_output_provider.dart';
import '../../../core/speech/speech_recognizer_provider.dart';
import '../data/chat_repository.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../domain/chat_turn_metadata.dart';

/// Phases of the user's outgoing turn:
///  - [idle]: composer enabled, no work in flight
///  - [streaming]: runtime events are being consumed.
enum ChatTurnPhase { idle, streaming }

/// UI-side state for one chat session: where we are in the send pipeline,
/// and the cancel handle for the in-flight turn.
///
/// Persisted state (sessions list, message timeline) lives in Drift and
/// flows through `chatSessionsStreamProvider` /
/// `chatMessagesStreamProvider`. This controller only models ephemeral
/// UI signals.
class ChatTurnState {
  const ChatTurnState({
    this.phase = ChatTurnPhase.idle,
    this.cancelToken,
    this.voiceListening = false,
    this.voiceTurnActive = false,
    this.voiceTranscript = '',
    this.voiceInputLane = InteractionInputLane.idle,
    this.voiceOutputLane = InteractionOutputLane.idle,
  });

  final ChatTurnPhase phase;
  final CancelToken? cancelToken;
  final bool voiceListening;
  final bool voiceTurnActive;
  final String voiceTranscript;
  final InteractionInputLane voiceInputLane;
  final InteractionOutputLane voiceOutputLane;

  bool get isIdle => phase == ChatTurnPhase.idle;
  bool get isStreaming => phase == ChatTurnPhase.streaming;
  bool get isBusy => phase != ChatTurnPhase.idle;
  bool get voiceActive => voiceListening;
  bool get canStartVoice => !isStreaming || voiceTurnActive;
  bool get voiceEndpointing =>
      voiceListening && voiceInputLane == InteractionInputLane.endpointing;
  bool get voiceSpeaking =>
      voiceTurnActive && _isVoiceOutputActive(voiceOutputLane);
  bool get voiceCapsuleVisible => voiceListening || voiceTurnActive;

  ChatTurnState copyWith({
    ChatTurnPhase? phase,
    CancelToken? cancelToken,
    bool? voiceListening,
    bool? voiceTurnActive,
    String? voiceTranscript,
    InteractionInputLane? voiceInputLane,
    InteractionOutputLane? voiceOutputLane,
  }) => ChatTurnState(
    phase: phase ?? this.phase,
    cancelToken: cancelToken ?? this.cancelToken,
    voiceListening: voiceListening ?? this.voiceListening,
    voiceTurnActive: voiceTurnActive ?? this.voiceTurnActive,
    voiceTranscript: voiceTranscript ?? this.voiceTranscript,
    voiceInputLane: voiceInputLane ?? this.voiceInputLane,
    voiceOutputLane: voiceOutputLane ?? this.voiceOutputLane,
  );
}

class ChatController extends StateNotifier<ChatTurnState> {
  ChatController({required this.ref, required this.sessionId})
    : super(const ChatTurnState());

  final Ref ref;
  final String sessionId;
  InteractionChatSession? _interactionSession;
  String? _interactionOwnerUserId;
  SpeechRecognizerBackend? _interactionBackend;

  InteractionChatSession _ensureInteractionSession({
    required ChatRepository repository,
    required String ownerUserId,
  }) {
    final existing = _interactionSession;
    final backend = ref.read(speechRecognizerBackendProvider);
    if (existing != null &&
        _interactionOwnerUserId == ownerUserId &&
        _interactionBackend == backend) {
      return existing;
    }
    if (existing != null) unawaited(existing.close());

    final session = InteractionChatSession(
      repository: repository,
      ownerUserId: ownerUserId,
      sessionId: sessionId,
      speechInput: ref.read(speechInputProvider),
      speechOutput: ref.read(speechOutputProvider),
      onTurnStarted: (request) {
        if (!mounted) return;
        state = ChatTurnState(
          phase: ChatTurnPhase.streaming,
          cancelToken: request.cancelToken,
          voiceListening: state.voiceListening,
          voiceTurnActive:
              state.voiceTurnActive ||
              request.origin == InteractionInputOrigin.voice,
          voiceTranscript: state.voiceTranscript,
          voiceInputLane: state.voiceInputLane,
          voiceOutputLane: state.voiceOutputLane,
        );
      },
      onTurnFinished: (request, _) {
        if (!mounted || !identical(state.cancelToken, request.cancelToken)) {
          return;
        }
        state = ChatTurnState(
          voiceListening: state.voiceListening,
          voiceTurnActive: request.origin == InteractionInputOrigin.voice
              ? state.voiceListening ||
                    _isVoiceOutputActive(state.voiceOutputLane)
              : state.voiceTurnActive,
          voiceTranscript: state.voiceTranscript,
          voiceInputLane: state.voiceInputLane,
          voiceOutputLane: state.voiceOutputLane,
        );
      },
      onSpeechEnded: ({required cancelled}) {
        if (!mounted) return;
        final keepVoiceTurn =
            !cancelled ||
            state.isStreaming ||
            _isVoiceOutputActive(state.voiceOutputLane);
        state = _withVoiceState(
          state,
          voiceListening: false,
          voiceTurnActive: keepVoiceTurn,
          voiceTranscript: keepVoiceTurn ? null : '',
          voiceInputLane: keepVoiceTurn
              ? state.voiceInputLane
              : InteractionInputLane.idle,
        );
      },
      onStateChanged: _onInteractionStateChanged,
      onSpeechOutputError: (error, stackTrace) {
        ref
            .read(loggerProvider)
            .event(
              'core.speech.output.failed',
              level: AppLogLevel.warning,
              fields: const {'outcome': 'failed', 'provider': 'system_tts'},
              error: error,
              stackTrace: stackTrace,
            );
      },
    );
    _interactionSession = session;
    _interactionOwnerUserId = ownerUserId;
    _interactionBackend = backend;
    return session;
  }

  /// Send [content] as the next user turn. Concurrent calls are
  /// rejected — the UI disables the send button while the pipeline is
  /// running.
  Future<void> send(
    String content, {
    String? systemContext,
    ChatTurnMetadata turnMetadata = const ChatTurnMetadata.empty(),
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || state.isBusy) return;

    // Device-only AI works in local-only mode too, so scope by the active
    // user id (synthetic [kLocalOnlyUserId] when account-less) rather than a
    // cloud session. `null` only before auth settles — the page guards that.
    final ownerUserId = ref.read(activeUserIdProvider);
    if (ownerUserId == null) return;

    final cancelToken = CancelToken();
    state = state.copyWith(
      phase: ChatTurnPhase.streaming,
      cancelToken: cancelToken,
    );

    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final session = _ensureInteractionSession(
        repository: repo,
        ownerUserId: ownerUserId,
      );
      session.configure(systemContext: systemContext);
      session.startTurn(
        turnMetadata.inputOrigin ?? InteractionInputOrigin.keyboard,
      );
      await session.commitInput(
        trimmed,
        origin: turnMetadata.inputOrigin,
        interactionResponse: turnMetadata.interactionResponse,
        cancelToken: cancelToken,
        resumeTurnId: turnMetadata.resumeTurnId,
      );
    } finally {
      if (mounted && identical(state.cancelToken, cancelToken)) {
        state = ChatTurnState(
          voiceListening: state.voiceListening,
          voiceTurnActive: state.voiceTurnActive,
          voiceTranscript: state.voiceTranscript,
          voiceInputLane: state.voiceInputLane,
          voiceOutputLane: state.voiceOutputLane,
        );
      }
    }
  }

  /// Starts the semantic voice lane for this chat session.
  ///
  /// A voice response may be interrupted while it is streaming; an unrelated
  /// keyboard response is left alone until it has produced output that the
  /// interaction coordinator can safely supersede.
  Future<void> startVoice({String? systemContext, String? model}) async {
    if (state.voiceListening) return;
    final ownerUserId = ref.read(activeUserIdProvider);
    if (ownerUserId == null) return;

    final repo = await ref.read(chatRepositoryProvider.future);
    final session = _ensureInteractionSession(
      repository: repo,
      ownerUserId: ownerUserId,
    );
    final interactionState = session.coordinator.state;
    final hasPendingInteraction = interactionState.pendingInteraction != null;
    final hasOutput = interactionState.outputLane != InteractionOutputLane.idle;
    if (state.isBusy && !hasOutput && !hasPendingInteraction) return;

    session.configure(systemContext: systemContext, model: model);
    await session.startVoice();
    if (!mounted) return;
    state = state.copyWith(voiceListening: true, voiceTurnActive: true);
  }

  Future<void> stopVoice() async {
    final session = _interactionSession;
    if (session == null) return;
    try {
      await session.stopVoice();
    } finally {
      if (mounted) {
        state = state.copyWith(voiceListening: false);
      }
    }
  }

  Future<void> cancelVoice() async {
    final session = _interactionSession;
    if (session == null) return;
    try {
      await session.cancelVoice();
    } finally {
      if (mounted) {
        final keepVoiceTurn =
            state.isStreaming || _isVoiceOutputActive(state.voiceOutputLane);
        state = _withVoiceState(
          state,
          voiceListening: false,
          voiceTurnActive: keepVoiceTurn,
          voiceTranscript: keepVoiceTurn ? null : '',
          voiceInputLane: keepVoiceTurn
              ? state.voiceInputLane
              : InteractionInputLane.idle,
        );
      }
    }
  }

  void _onInteractionStateChanged(InteractionState interaction) {
    if (!mounted) return;
    final shouldFinishVoiceTurn =
        state.voiceTurnActive &&
        !state.voiceListening &&
        !state.isStreaming &&
        interaction.outputLane == InteractionOutputLane.idle;
    state = _withVoiceState(
      state,
      voiceTurnActive: shouldFinishVoiceTurn ? false : state.voiceTurnActive,
      voiceTranscript: interaction.transcript,
      voiceInputLane: interaction.inputLane,
      voiceOutputLane: interaction.outputLane,
    );
  }

  Future<void> chooseDecision({
    required String messageId,
    required String toolInvocationId,
    required DecisionSelection selection,
    String? systemContext,
    Map<String, Object?>? invocationTrace,
  }) async {
    if (state.isBusy) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    final interactionResponse = await repo.recordDecisionSelection(
      sessionId: sessionId,
      messageId: messageId,
      toolInvocationId: toolInvocationId,
      selection: selection,
    );
    await send(
      selection.reply,
      systemContext: systemContext,
      turnMetadata: ChatTurnMetadata.forDecision(
        selection: selection,
        messageId: messageId,
        toolInvocationId: toolInvocationId,
        interactionResponse: interactionResponse,
        invocationTrace: invocationTrace,
      ),
    );
  }

  /// Branch-replace a past user turn: discards the message + every
  /// reply (and follow-up turn) after it, then sends [newContent] as
  /// a fresh user turn. No-op when a turn is in flight, the new
  /// content is empty, or the message id can't be found / isn't a
  /// user turn.
  Future<void> editAndResend({
    required String messageId,
    required String newContent,
    String? systemContext,
  }) async {
    if (state.isBusy) return;
    final trimmed = newContent.trim();
    if (trimmed.isEmpty) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    final ok = await repo.discardFromUserMessage(
      sessionId: sessionId,
      messageId: messageId,
    );
    if (!ok) return;
    await send(trimmed, systemContext: systemContext);
  }

  /// Re-run the last assistant turn. Discards both the assistant
  /// message and the user message that produced it, then re-sends the
  /// user content through [send]. No-op while a turn is in flight, or
  /// when there's nothing eligible to regenerate (no assistant message,
  /// no preceding user message, or the assistant is still streaming).
  Future<void> regenerateLast({String? systemContext}) async {
    if (state.isBusy) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    final priorContent = await repo.prepareRegenerateLastAssistant(sessionId);
    if (priorContent == null) return;
    await send(priorContent, systemContext: systemContext);
  }

  /// Cancel the in-flight stream. Repository will mark the assistant
  /// turn as `errored` with reason "已取消".
  void cancel() {
    final token = state.cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('user cancelled');
    }
  }

  @override
  void dispose() {
    unawaited(_interactionSession?.close());
    super.dispose();
  }
}

bool _isVoiceOutputActive(InteractionOutputLane lane) =>
    lane == InteractionOutputLane.synthesizing ||
    lane == InteractionOutputLane.playing ||
    lane == InteractionOutputLane.paused;

ChatTurnState _withVoiceState(
  ChatTurnState current, {
  bool? voiceListening,
  bool? voiceTurnActive,
  String? voiceTranscript,
  InteractionInputLane? voiceInputLane,
  InteractionOutputLane? voiceOutputLane,
}) => ChatTurnState(
  phase: current.phase,
  cancelToken: current.cancelToken,
  voiceListening: voiceListening ?? current.voiceListening,
  voiceTurnActive: voiceTurnActive ?? current.voiceTurnActive,
  voiceTranscript: voiceTranscript ?? current.voiceTranscript,
  voiceInputLane: voiceInputLane ?? current.voiceInputLane,
  voiceOutputLane: voiceOutputLane ?? current.voiceOutputLane,
);

/// Per-session controller. Riverpod auto-disposes when the chat page
/// pops, which also cancels any in-flight turn via the `mounted` check.
final chatControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatController, ChatTurnState, String>(
      (ref, sessionId) => ChatController(ref: ref, sessionId: sessionId),
    );
