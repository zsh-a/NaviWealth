import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/ai/contracts/chat_events.dart';
import '../../core/ai/contracts/interaction.dart';
import '../../core/ai/intent/ai_intent_invocation.dart';
import '../../core/ai/session/interaction_ids.dart';
import '../../core/ai/session/interaction_state.dart';
import '../../core/speech/speech_input.dart';
import '../../core/speech/speech_output.dart';
import '../../core/speech/speech_recognizer.dart';
import '../../features/ai_chat/data/chat_repository.dart';
import '../../features/ai_chat/domain/chat_turn_metadata.dart';
import 'agent_event_adapter.dart';
import 'interaction_session_coordinator.dart';
import 'speech_output_bridge.dart';

/// Host composition for one real ChatRepository-backed InteractionSession.
///
/// ChatRepository continues to own message writes, ChatTurn continuation,
/// tool dispatch, and trace persistence. This class only projects its
/// provider-neutral events into session timing and speech delivery.
final class InteractionChatSession {
  factory InteractionChatSession({
    required ChatRepository repository,
    required String ownerUserId,
    required String sessionId,
    required SpeechOutput speechOutput,
    SpeechInput? speechInput,
    AiIntentInvocation? invocation,
    String? systemContext,
    String? model,
    void Function(InteractionTurnRequest request)? onTurnStarted,
    void Function(InteractionTurnRequest request, SendOutcome outcome)?
    onTurnFinished,
    void Function({required bool cancelled})? onSpeechEnded,
    void Function(SpeechRecognitionException error, StackTrace stackTrace)?
    onSpeechError,
    void Function(InteractionState state)? onStateChanged,
    void Function(Object error, StackTrace stackTrace)? onTurnError,
    void Function(Object error, StackTrace stackTrace)? onSpeechOutputError,
  }) {
    late final InteractionChatSession session;
    final coordinator = InteractionSessionCoordinator(
      sessionId: SessionId(sessionId),
      invocation: invocation,
      speechInput: speechInput,
      onTurnCommitted: (request) => session._handleTurn(request),
      onBargeInCandidate: () => unawaited(session._output.pause()),
      onFalseInterruption: () => unawaited(session._output.resume()),
      onEpochAdvanced: (staleEpoch) {
        session._cancelEpoch(staleEpoch);
        unawaited(session._output.interrupt(staleEpoch: staleEpoch));
      },
      onSpeechEnded: onSpeechEnded,
      onSpeechError: onSpeechError,
      onStateChanged: onStateChanged,
      onTurnError: onTurnError,
    );
    final output = SerializedSpeechOutputBridge(
      speechOutput: speechOutput,
      coordinator: coordinator,
      onProviderError: onSpeechOutputError,
    );
    session = InteractionChatSession._(
      repository: repository,
      ownerUserId: ownerUserId,
      systemContext: systemContext,
      model: model,
      coordinator: coordinator,
      output: output,
      onTurnStarted: onTurnStarted,
      onTurnFinished: onTurnFinished,
    );
    return session;
  }

  InteractionChatSession._({
    required ChatRepository repository,
    required String ownerUserId,
    required String? systemContext,
    required String? model,
    required InteractionSessionCoordinator coordinator,
    required SerializedSpeechOutputBridge output,
    required void Function(InteractionTurnRequest request)? onTurnStarted,
    required void Function(InteractionTurnRequest request, SendOutcome outcome)?
    onTurnFinished,
  }) : _repository = repository,
       _ownerUserId = ownerUserId,
       _systemContext = systemContext,
       _model = model,
       _coordinator = coordinator,
       _output = output,
       _onTurnStarted = onTurnStarted,
       _onTurnFinished = onTurnFinished;

  final ChatRepository _repository;
  final String _ownerUserId;
  String? _systemContext;
  String? _model;
  final InteractionSessionCoordinator _coordinator;
  final SerializedSpeechOutputBridge _output;
  final void Function(InteractionTurnRequest request)? _onTurnStarted;
  final void Function(InteractionTurnRequest request, SendOutcome outcome)?
  _onTurnFinished;
  final Map<int, CancelToken> _activeCancelTokens = <int, CancelToken>{};
  bool _closed = false;

  InteractionSessionCoordinator get coordinator => _coordinator;

  Future<void> startVoice() => _coordinator.startVoice();

  Future<void> stopVoice() => _coordinator.stopVoice();

  Future<void> cancelVoice() => _coordinator.cancelVoice();

  void configure({String? systemContext, String? model}) {
    if (_closed) return;
    _systemContext = systemContext;
    _model = model;
  }

  TurnId startTurn(InteractionInputOrigin origin) =>
      _coordinator.startTurn(origin);

  Future<void> commitInput(
    String text, {
    InteractionInputOrigin? origin,
    AiInteractionResponse? interactionResponse,
    CancelToken? cancelToken,
    String? systemContext,
    String? model,
    String? resumeTurnId,
  }) => _coordinator.commitInput(
    text,
    origin: origin,
    interactionResponse: interactionResponse,
    cancelToken: cancelToken,
    systemContext: systemContext,
    model: model,
    resumeTurnId: resumeTurnId,
  );

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final token in _activeCancelTokens.values) {
      if (!token.isCancelled) token.cancel('interaction session closed');
    }
    await _output.close();
    await _coordinator.close();
  }

  Future<void> _handleTurn(InteractionTurnRequest request) async {
    if (!_owns(request)) return;

    final effectiveRequest = request.cancelToken == null
        ? InteractionTurnRequest(
            sessionId: request.sessionId,
            turnId: request.turnId,
            epoch: request.epoch,
            text: request.text,
            origin: request.origin,
            cancelToken: CancelToken(),
            systemContext: request.systemContext,
            model: request.model,
            interactionResponse: request.interactionResponse,
            resumeTurnId: request.resumeTurnId,
          )
        : request;
    final cancelToken = effectiveRequest.cancelToken!;
    _activeCancelTokens[effectiveRequest.epoch.value] = cancelToken;
    _onTurnStarted?.call(effectiveRequest);
    _coordinator.agentStarted();

    final speakOutput = effectiveRequest.origin == InteractionInputOrigin.voice;
    var sawTerminal = false;
    final adapter = AgentEventAdapter(
      _coordinator,
      onOutputSegment: speakOutput ? _output.enqueue : null,
      onOutputFinished: (epoch, {required interrupted}) {
        sawTerminal = true;
        if (speakOutput) {
          unawaited(_output.finish(epoch, interrupted: interrupted));
        } else {
          _coordinator.outputPlaybackStopped(interrupted: interrupted);
        }
      },
    );

    var outcome = SendOutcome.completed;
    try {
      outcome = await _repository.sendMessage(
        sessionId: effectiveRequest.sessionId.value,
        ownerUserId: _ownerUserId,
        content: effectiveRequest.text,
        systemContext: effectiveRequest.systemContext ?? _systemContext,
        model: effectiveRequest.model ?? _model,
        turnMetadata: ChatTurnMetadata(
          interactionResponse: effectiveRequest.interactionResponse,
          inputOrigin: effectiveRequest.origin,
          resumeTurnId: effectiveRequest.resumeTurnId,
        ),
        onAiChatEvent: (event) {
          if (event is DoneEvent || event is ErrorEvent) {
            sawTerminal = true;
          }
          adapter.accept(
            event,
            turnId: effectiveRequest.turnId,
            epoch: effectiveRequest.epoch,
          );
        },
        cancelToken: cancelToken,
      );

      if (!sawTerminal && _owns(effectiveRequest)) {
        switch (outcome) {
          case SendOutcome.completed:
            _coordinator.agentFinished();
            _finishOutput(
              effectiveRequest.epoch,
              speakOutput: speakOutput,
              interrupted: false,
            );
          case SendOutcome.errored:
            _coordinator.agentFailed();
            _finishOutput(
              effectiveRequest.epoch,
              speakOutput: speakOutput,
              interrupted: true,
            );
          case SendOutcome.cancelled:
            _coordinator.agentCancelled();
            _finishOutput(
              effectiveRequest.epoch,
              speakOutput: speakOutput,
              interrupted: true,
            );
        }
      } else if (outcome == SendOutcome.cancelled && _owns(effectiveRequest)) {
        _coordinator.agentCancelled();
      }
    } on Object {
      outcome = SendOutcome.errored;
      if (_owns(effectiveRequest)) {
        _coordinator.agentFailed();
        _finishOutput(
          effectiveRequest.epoch,
          speakOutput: speakOutput,
          interrupted: true,
        );
      }
      rethrow;
    } finally {
      if (identical(
        _activeCancelTokens[effectiveRequest.epoch.value],
        cancelToken,
      )) {
        _activeCancelTokens.remove(effectiveRequest.epoch.value);
      }
      _onTurnFinished?.call(effectiveRequest, outcome);
    }
  }

  void _finishOutput(
    ResponseEpoch epoch, {
    required bool speakOutput,
    required bool interrupted,
  }) {
    if (speakOutput) {
      unawaited(_output.finish(epoch, interrupted: interrupted));
    } else if (_ownsEpoch(epoch)) {
      _coordinator.outputPlaybackStopped(interrupted: interrupted);
    }
  }

  bool _ownsEpoch(ResponseEpoch epoch) =>
      !_closed && _coordinator.state.responseEpoch == epoch;

  void _cancelEpoch(ResponseEpoch epoch) {
    final token = _activeCancelTokens[epoch.value];
    if (token != null && !token.isCancelled) {
      token.cancel('voice interruption');
    }
  }

  bool _owns(InteractionTurnRequest request) =>
      !_closed &&
      _coordinator.state.activeTurnId == request.turnId &&
      _coordinator.state.responseEpoch == request.epoch;
}
