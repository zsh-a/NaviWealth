import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/interaction/interaction_chat_session.dart';
import '../../../core/ai/session/interaction_state.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/providers.dart';
import '../../../core/speech/speech_input.dart';
import '../../../core/speech/speech_output.dart';
import '../../../core/speech/speech_output_provider.dart';
import '../../../core/speech/speech_recognizer.dart';
import '../../../core/speech/speech_recognizer_provider.dart';
import '../data/chat_repository.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../domain/chat_turn_metadata.dart';

/// Phases of the user's outgoing turn:
///  - [idle]: composer enabled, no work in flight
///  - [streaming]: runtime events are being consumed.
enum ChatTurnPhase { idle, streaming }

/// User-visible lifecycle of one voice interaction. This is intentionally
/// finer grained than the modality-agnostic InteractionSession lanes so a
/// slow native permission/model startup still has immediate UI feedback.
enum VoiceLifecyclePhase {
  idle,
  preparing,
  permission,
  ready,
  listening,
  endpointing,
  thinking,
  speaking,
  error,
}

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
    this.voicePhase = VoiceLifecyclePhase.idle,
    this.voiceTranscript = '',
    this.voiceErrorCode,
    this.voiceOutputErrorCode,
    this.voiceCapabilities = SpeechRecognizerCapabilities.unknown,
    this.voiceInputLane = InteractionInputLane.idle,
    this.voiceOutputLane = InteractionOutputLane.idle,
  });

  final ChatTurnPhase phase;
  final CancelToken? cancelToken;
  final bool voiceListening;
  final bool voiceTurnActive;
  final VoiceLifecyclePhase voicePhase;
  final String voiceTranscript;
  final SpeechRecognitionErrorCode? voiceErrorCode;
  final SpeechOutputErrorCode? voiceOutputErrorCode;
  final SpeechRecognizerCapabilities voiceCapabilities;
  final InteractionInputLane voiceInputLane;
  final InteractionOutputLane voiceOutputLane;

  bool get isIdle => phase == ChatTurnPhase.idle;
  bool get isStreaming => phase == ChatTurnPhase.streaming;
  bool get isBusy => phase != ChatTurnPhase.idle;
  bool get voiceActive => voiceListening;
  bool get voicePreparing => switch (voicePhase) {
    VoiceLifecyclePhase.preparing ||
    VoiceLifecyclePhase.permission ||
    VoiceLifecyclePhase.ready => true,
    _ => false,
  };
  bool get voiceFullDuplex =>
      voiceCapabilities.fullDuplex && voiceCapabilities.supportsBargeIn;
  bool get canStartVoice =>
      !voicePreparing && (!isStreaming || voiceTurnActive);
  bool get voiceEndpointing =>
      voiceListening && voiceInputLane == InteractionInputLane.endpointing;
  bool get voiceSpeaking =>
      voiceTurnActive && _isVoiceOutputActive(voiceOutputLane);
  bool get voiceCapsuleVisible =>
      voicePreparing || voiceListening || voiceTurnActive;

  ChatTurnState copyWith({
    ChatTurnPhase? phase,
    CancelToken? cancelToken,
    bool? voiceListening,
    bool? voiceTurnActive,
    VoiceLifecyclePhase? voicePhase,
    String? voiceTranscript,
    InteractionInputLane? voiceInputLane,
    InteractionOutputLane? voiceOutputLane,
    SpeechRecognitionErrorCode? voiceErrorCode,
    SpeechOutputErrorCode? voiceOutputErrorCode,
    SpeechRecognizerCapabilities? voiceCapabilities,
    bool clearVoiceErrorCode = false,
    bool clearVoiceOutputErrorCode = false,
  }) => ChatTurnState(
    phase: phase ?? this.phase,
    cancelToken: cancelToken ?? this.cancelToken,
    voiceListening: voiceListening ?? this.voiceListening,
    voiceTurnActive: voiceTurnActive ?? this.voiceTurnActive,
    voicePhase: voicePhase ?? this.voicePhase,
    voiceTranscript: voiceTranscript ?? this.voiceTranscript,
    voiceInputLane: voiceInputLane ?? this.voiceInputLane,
    voiceOutputLane: voiceOutputLane ?? this.voiceOutputLane,
    voiceErrorCode: clearVoiceErrorCode
        ? null
        : voiceErrorCode ?? this.voiceErrorCode,
    voiceOutputErrorCode: clearVoiceOutputErrorCode
        ? null
        : voiceOutputErrorCode ?? this.voiceOutputErrorCode,
    voiceCapabilities: voiceCapabilities ?? this.voiceCapabilities,
  );
}

class ChatController extends StateNotifier<ChatTurnState>
    with WidgetsBindingObserver {
  ChatController({required this.ref, required this.sessionId})
    : super(const ChatTurnState()) {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => _warmupCancelled = true);
    unawaited(_warmUpVoiceCapabilities());
  }

  final Ref ref;
  final String sessionId;
  InteractionChatSession? _interactionSession;
  String? _interactionOwnerUserId;
  SpeechRecognizerBackend? _interactionBackend;
  Future<void>? _voiceStarting;
  bool _voiceCancelRequested = false;
  bool _warmupCancelled = false;

  Future<void> _warmUpVoiceCapabilities() async {
    try {
      if (_warmupCancelled || !ref.mounted) return;
      final input = ref.read(speechInputProvider);
      if (input case final SpeechInputPreparation preparation) {
        await preparation.prepare();
      }
      if (_warmupCancelled || !ref.mounted) return;
      final output = ref.read(speechOutputProvider);
      if (output case final SpeechOutputPreparation preparation) {
        await preparation.prepare();
      }
    } on Object catch (error, stackTrace) {
      if (_warmupCancelled || !ref.mounted) return;
      ref
          .read(loggerProvider)
          .event(
            'core.speech.warmup.failed',
            level: AppLogLevel.info,
            fields: <String, Object?>{
              'outcome': 'warmup_failed',
              'error_code': diagnosticErrorCode(error),
            },
            error: error,
            stackTrace: stackTrace,
          );
    }
  }

  Future<InteractionChatSession> _ensureInteractionSession({
    required ChatRepository repository,
    required String ownerUserId,
  }) async {
    final existing = _interactionSession;
    final backend = ref.read(speechRecognizerBackendProvider);
    if (existing != null &&
        _interactionOwnerUserId == ownerUserId &&
        _interactionBackend == backend) {
      return existing;
    }
    // The old session may still own the process-wide microphone lease. Wait
    // for its cancellation before creating a session for a changed backend
    // or user; otherwise the new voice start can race into session_busy.
    if (existing != null) await existing.close();

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
          voicePhase: request.origin == InteractionInputOrigin.voice
              ? VoiceLifecyclePhase.thinking
              : state.voicePhase,
          voiceTranscript: state.voiceTranscript,
          voiceInputLane: state.voiceInputLane,
          voiceOutputLane: state.voiceOutputLane,
          voiceErrorCode: state.voiceErrorCode,
          voiceOutputErrorCode: state.voiceOutputErrorCode,
          voiceCapabilities: state.voiceCapabilities,
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
          voicePhase:
              request.origin == InteractionInputOrigin.voice &&
                  !_isVoiceOutputActive(state.voiceOutputLane) &&
                  !state.voiceListening
              ? VoiceLifecyclePhase.idle
              : state.voicePhase,
          voiceTranscript: state.voiceTranscript,
          voiceInputLane: state.voiceInputLane,
          voiceOutputLane: state.voiceOutputLane,
          voiceErrorCode: state.voiceErrorCode,
          voiceOutputErrorCode: state.voiceOutputErrorCode,
          voiceCapabilities: state.voiceCapabilities,
        );
      },
      onSpeechEnded: ({required cancelled}) {
        if (!mounted) return;
        final keepVoiceTurn =
            state.isStreaming || _isVoiceOutputActive(state.voiceOutputLane);
        state = _withVoiceState(
          state,
          voiceListening: false,
          voiceTurnActive: keepVoiceTurn,
          voicePhase: keepVoiceTurn
              ? state.voicePhase
              : VoiceLifecyclePhase.idle,
          voiceTranscript: keepVoiceTurn ? null : '',
          voiceInputLane: keepVoiceTurn
              ? state.voiceInputLane
              : InteractionInputLane.idle,
        );
      },
      onSpeechStatus: _onSpeechStatus,
      onSpeechCaptureStarted: (_) => _onSpeechCaptureStarted(),
      onSpeechError: _onSpeechInputError,
      onStateChanged: _onInteractionStateChanged,
      onSpeechOutputError: (error, stackTrace) {
        ref
            .read(loggerProvider)
            .event(
              'core.speech.output.failed',
              level: AppLogLevel.warning,
              fields: {
                'outcome': 'failed',
                'provider': 'system_tts',
                'error_code': error is SpeechOutputException
                    ? error.code.diagnosticCode
                    : diagnosticErrorCode(error),
              },
              error: error,
              stackTrace: stackTrace,
            );
        if (mounted && error is SpeechOutputException) {
          state = _withVoiceState(
            state,
            voicePhase: VoiceLifecyclePhase.error,
            voiceOutputErrorCode: error.code,
          );
        }
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
      final session = await _ensureInteractionSession(
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
          voicePhase: state.voicePhase,
          voiceTranscript: state.voiceTranscript,
          voiceInputLane: state.voiceInputLane,
          voiceOutputLane: state.voiceOutputLane,
          voiceErrorCode: state.voiceErrorCode,
          voiceOutputErrorCode: state.voiceOutputErrorCode,
          voiceCapabilities: state.voiceCapabilities,
        );
      }
    }
  }

  /// Starts the semantic voice lane for this chat session.
  ///
  /// A voice response may be interrupted while it is streaming; an unrelated
  /// keyboard response is left alone until it has produced output that the
  /// interaction coordinator can safely supersede.
  Future<void> startVoice({String? systemContext, String? model}) {
    final starting = _voiceStarting;
    if (starting != null || state.voiceListening || state.voicePreparing) {
      return starting ?? Future<void>.value();
    }
    final future = _startVoice(systemContext: systemContext, model: model);
    _voiceStarting = future;
    return future.whenComplete(() {
      if (identical(_voiceStarting, future)) _voiceStarting = null;
    });
  }

  Future<void> _startVoice({String? systemContext, String? model}) async {
    _voiceCancelRequested = false;
    if (mounted) {
      // This assignment intentionally happens before the repository/session
      // futures. The user sees a cancellable capsule in the same frame as the
      // tap instead of waiting for Drift/provider setup to finish.
      state = state.copyWith(
        voicePhase: VoiceLifecyclePhase.preparing,
        voiceListening: false,
        voiceTurnActive: state.voiceTurnActive,
        voiceTranscript: '',
        voiceCapabilities: SpeechRecognizerCapabilities.unknown,
        clearVoiceErrorCode: true,
        clearVoiceOutputErrorCode: true,
      );
    }
    final ownerUserId = ref.read(activeUserIdProvider);
    if (ownerUserId == null) {
      if (mounted) {
        state = state.copyWith(voicePhase: VoiceLifecyclePhase.error);
      }
      return;
    }

    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final session = await _ensureInteractionSession(
        repository: repo,
        ownerUserId: ownerUserId,
      );
      if (_voiceCancelRequested) {
        await session.cancelVoice();
        return;
      }
      final interactionState = session.coordinator.state;
      final hasPendingInteraction = interactionState.pendingInteraction != null;
      final hasOutput =
          interactionState.outputLane != InteractionOutputLane.idle;
      if (state.isBusy && !hasOutput && !hasPendingInteraction) {
        if (mounted) {
          state = state.copyWith(voicePhase: VoiceLifecyclePhase.idle);
        }
        return;
      }

      session.configure(systemContext: systemContext, model: model);
      await session.startVoice();
      if (_voiceCancelRequested) {
        await session.cancelVoice();
        return;
      }
      if (!mounted) return;
      state = state.copyWith(
        voiceListening: true,
        voiceTurnActive: true,
        voicePhase: VoiceLifecyclePhase.ready,
        clearVoiceErrorCode: true,
        clearVoiceOutputErrorCode: true,
      );
    } on Object catch (error, stackTrace) {
      if (_voiceCancelRequested) return;
      final speechError = error is SpeechRecognitionException
          ? error
          : SpeechRecognitionException(
              SpeechRecognitionErrorCode.runtimeUnavailable,
              'Speech recognition failed to start',
              cause: error,
            );
      _onSpeechInputError(speechError, stackTrace);
      rethrow;
    }
  }

  Future<void> stopVoice() async {
    final session = _interactionSession;
    if (session == null) return;
    try {
      await session.stopVoice();
    } finally {
      if (mounted) {
        state = state.copyWith(
          voiceListening: false,
          voicePhase: state.voiceTurnActive
              ? state.voicePhase
              : VoiceLifecyclePhase.idle,
          clearVoiceErrorCode: true,
        );
      }
    }
  }

  Future<void> cancelVoice() async {
    final starting = _voiceStarting;
    if (starting != null) {
      _voiceCancelRequested = true;
      final session = _interactionSession;
      if (session != null) unawaited(session.cancelVoice());
      try {
        await starting;
      } on Object {
        // The user already cancelled the preparation operation.
      }
      if (mounted) {
        state = _withVoiceState(
          state,
          voiceListening: false,
          voiceTurnActive: false,
          voicePhase: VoiceLifecyclePhase.idle,
          voiceTranscript: '',
          voiceInputLane: InteractionInputLane.idle,
          clearVoiceErrorCode: true,
          clearVoiceOutputErrorCode: true,
        );
      }
      return;
    }
    final session = _interactionSession;
    if (session == null) return;
    final outputWasActive = _isVoiceOutputActive(state.voiceOutputLane);
    try {
      if (state.voiceListening) await session.cancelVoice();
      if (outputWasActive) await session.stopOutput();
    } finally {
      if (mounted) {
        final keepVoiceTurn = state.isStreaming && !outputWasActive;
        state = _withVoiceState(
          state,
          voiceListening: false,
          voiceTurnActive: keepVoiceTurn,
          voicePhase: keepVoiceTurn
              ? VoiceLifecyclePhase.thinking
              : VoiceLifecyclePhase.idle,
          voiceTranscript: keepVoiceTurn ? null : '',
          voiceInputLane: keepVoiceTurn
              ? state.voiceInputLane
              : InteractionInputLane.idle,
          clearVoiceErrorCode: true,
          clearVoiceOutputErrorCode: true,
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
    final nextPhase = shouldFinishVoiceTurn
        ? VoiceLifecyclePhase.idle
        : _voicePhaseForInteraction(interaction);
    state = _withVoiceState(
      state,
      voiceTurnActive: shouldFinishVoiceTurn ? false : state.voiceTurnActive,
      voicePhase: nextPhase,
      voiceTranscript: interaction.transcript,
      voiceInputLane: interaction.inputLane,
      voiceOutputLane: interaction.outputLane,
    );
  }

  void _onSpeechStatus(SpeechRecognizerStatus status) {
    if (!mounted) return;
    final phase = switch (status.availability) {
      SpeechRecognizerAvailability.permissionDenied =>
        VoiceLifecyclePhase.permission,
      SpeechRecognizerAvailability.ready when state.voicePreparing =>
        VoiceLifecyclePhase.ready,
      _ => state.voicePhase,
    };
    state = _withVoiceState(
      state,
      voicePhase: phase,
      voiceCapabilities: status.capabilities,
    );
  }

  void _onSpeechCaptureStarted() {
    if (!mounted) return;
    state = _withVoiceState(
      state,
      voiceListening: true,
      voiceTurnActive: true,
      voicePhase: VoiceLifecyclePhase.listening,
    );
  }

  VoiceLifecyclePhase _voicePhaseForInteraction(InteractionState interaction) {
    if (state.voiceErrorCode != null || state.voiceOutputErrorCode != null) {
      return VoiceLifecyclePhase.error;
    }
    if (state.voiceListening) {
      return interaction.inputLane == InteractionInputLane.endpointing ||
              interaction.inputLane == InteractionInputLane.committed
          ? VoiceLifecyclePhase.endpointing
          : VoiceLifecyclePhase.listening;
    }
    if (state.voiceTurnActive && _isVoiceOutputActive(interaction.outputLane)) {
      return VoiceLifecyclePhase.speaking;
    }
    if (state.voiceTurnActive && state.isStreaming) {
      return VoiceLifecyclePhase.thinking;
    }
    if (state.voicePreparing) return state.voicePhase;
    return state.voiceTurnActive
        ? VoiceLifecyclePhase.thinking
        : VoiceLifecyclePhase.idle;
  }

  void _onSpeechInputError(
    SpeechRecognitionException error,
    StackTrace stackTrace,
  ) {
    if (!mounted) return;
    final backend = _interactionBackend?.name;
    ref
        .read(loggerProvider)
        .event(
          'core.speech.input.failed',
          level: AppLogLevel.warning,
          fields: {
            'outcome': 'failed',
            'provider': backend ?? 'unknown',
            'error_code': error.code.diagnosticCode,
          },
          error: error,
          stackTrace: stackTrace,
        );
    final keepVoiceTurn =
        state.isStreaming || _isVoiceOutputActive(state.voiceOutputLane);
    state = _withVoiceState(
      state,
      voiceListening: false,
      voiceTurnActive: keepVoiceTurn,
      voicePhase: VoiceLifecyclePhase.error,
      voiceTranscript: keepVoiceTurn ? null : '',
      voiceInputLane: keepVoiceTurn
          ? state.voiceInputLane
          : InteractionInputLane.idle,
      voiceErrorCode: error.code,
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    unawaited(_stopVoiceForLifecycle());
  }

  Future<void> _stopVoiceForLifecycle() async {
    final starting = _voiceStarting;
    if (starting != null) {
      await cancelVoice();
    } else {
      final session = _interactionSession;
      if (session == null) return;
      try {
        await session.cancelVoice();
        await session.stopOutput();
      } on Object {
        // Background teardown is best effort; the native host also owns a
        // terminal cancellation boundary for microphone resources.
      }
    }
    if (!mounted) return;
    state = _withVoiceState(
      state,
      voiceListening: false,
      voiceTurnActive: false,
      voicePhase: VoiceLifecyclePhase.idle,
      voiceTranscript: '',
      voiceInputLane: InteractionInputLane.idle,
      voiceOutputLane: InteractionOutputLane.idle,
      clearVoiceErrorCode: true,
      clearVoiceOutputErrorCode: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _warmupCancelled = true;
    _voiceCancelRequested = true;
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
  VoiceLifecyclePhase? voicePhase,
  String? voiceTranscript,
  InteractionInputLane? voiceInputLane,
  InteractionOutputLane? voiceOutputLane,
  SpeechRecognitionErrorCode? voiceErrorCode,
  SpeechOutputErrorCode? voiceOutputErrorCode,
  SpeechRecognizerCapabilities? voiceCapabilities,
  bool clearVoiceErrorCode = false,
  bool clearVoiceOutputErrorCode = false,
}) => ChatTurnState(
  phase: current.phase,
  cancelToken: current.cancelToken,
  voiceListening: voiceListening ?? current.voiceListening,
  voiceTurnActive: voiceTurnActive ?? current.voiceTurnActive,
  voicePhase: voicePhase ?? current.voicePhase,
  voiceTranscript: voiceTranscript ?? current.voiceTranscript,
  voiceInputLane: voiceInputLane ?? current.voiceInputLane,
  voiceOutputLane: voiceOutputLane ?? current.voiceOutputLane,
  voiceErrorCode: clearVoiceErrorCode
      ? null
      : voiceErrorCode ?? current.voiceErrorCode,
  voiceOutputErrorCode: clearVoiceOutputErrorCode
      ? null
      : voiceOutputErrorCode ?? current.voiceOutputErrorCode,
  voiceCapabilities: voiceCapabilities ?? current.voiceCapabilities,
);

/// Per-session controller. Riverpod auto-disposes when the chat page
/// pops, which also cancels any in-flight turn via the `mounted` check.
final chatControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatController, ChatTurnState, String>(
      (ref, sessionId) => ChatController(ref: ref, sessionId: sessionId),
    );
