import 'dart:async';

import '../../core/ai/contracts/chat_events.dart';
import '../../core/ai/contracts/interaction.dart';
import '../../core/ai/intent/ai_intent_invocation.dart';
import '../../core/ai/session/interaction_ids.dart';
import '../../core/ai/session/interaction_state.dart';
import '../../core/speech/speech_input.dart';
import '../../core/speech/speech_output.dart';
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
  }) {
    late final InteractionChatSession session;
    final coordinator = InteractionSessionCoordinator(
      sessionId: SessionId(sessionId),
      invocation: invocation,
      speechInput: speechInput,
      onTurnCommitted: (request) => session._handleTurn(request),
      onBargeInCandidate: () => unawaited(session._output.pause()),
      onFalseInterruption: () => unawaited(session._output.resume()),
      onEpochAdvanced: (staleEpoch) =>
          unawaited(session._output.interrupt(staleEpoch: staleEpoch)),
    );
    final output = SerializedSpeechOutputBridge(
      speechOutput: speechOutput,
      coordinator: coordinator,
    );
    session = InteractionChatSession._(
      repository: repository,
      ownerUserId: ownerUserId,
      systemContext: systemContext,
      model: model,
      coordinator: coordinator,
      output: output,
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
  }) : _repository = repository,
       _ownerUserId = ownerUserId,
       _systemContext = systemContext,
       _model = model,
       _coordinator = coordinator,
       _output = output;

  final ChatRepository _repository;
  final String _ownerUserId;
  final String? _systemContext;
  final String? _model;
  final InteractionSessionCoordinator _coordinator;
  final SerializedSpeechOutputBridge _output;
  bool _closed = false;

  InteractionSessionCoordinator get coordinator => _coordinator;

  Future<void> startVoice() => _coordinator.startVoice();

  Future<void> stopVoice() => _coordinator.stopVoice();

  TurnId startTurn(InteractionInputOrigin origin) =>
      _coordinator.startTurn(origin);

  void commitInput(
    String text, {
    InteractionInputOrigin? origin,
    AiInteractionResponse? interactionResponse,
  }) => _coordinator.commitInput(
    text,
    origin: origin,
    interactionResponse: interactionResponse,
  );

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _output.close();
    await _coordinator.close();
  }

  Future<void> _handleTurn(InteractionTurnRequest request) async {
    if (!_owns(request)) return;
    _coordinator.agentStarted();

    var sawTerminal = false;
    final adapter = AgentEventAdapter(
      _coordinator,
      onOutputSegment: _output.enqueue,
      onOutputFinished: (epoch, {required interrupted}) {
        sawTerminal = true;
        unawaited(_output.finish(epoch, interrupted: interrupted));
      },
    );

    try {
      final outcome = await _repository.sendMessage(
        sessionId: request.sessionId.value,
        ownerUserId: _ownerUserId,
        content: request.text,
        systemContext: _systemContext,
        model: _model,
        turnMetadata: ChatTurnMetadata(
          interactionResponse: request.interactionResponse,
          inputOrigin: request.origin,
          resumeTurnId: request.resumeTurnId,
        ),
        onAiChatEvent: (event) {
          if (event is DoneEvent || event is ErrorEvent) {
            sawTerminal = true;
          }
          adapter.accept(event, turnId: request.turnId, epoch: request.epoch);
        },
      );

      if (!sawTerminal && _owns(request)) {
        switch (outcome) {
          case SendOutcome.completed:
            _coordinator.agentFinished();
            unawaited(_output.finish(request.epoch, interrupted: false));
          case SendOutcome.errored:
            _coordinator.agentFailed();
            unawaited(_output.finish(request.epoch, interrupted: true));
          case SendOutcome.cancelled:
            _coordinator.agentCancelled();
            unawaited(_output.finish(request.epoch, interrupted: true));
        }
      } else if (outcome == SendOutcome.cancelled && _owns(request)) {
        _coordinator.agentCancelled();
      }
    } on Object {
      if (_owns(request)) {
        _coordinator.agentFailed();
        unawaited(_output.finish(request.epoch, interrupted: true));
      }
    }
  }

  bool _owns(InteractionTurnRequest request) =>
      !_closed &&
      _coordinator.state.activeTurnId == request.turnId &&
      _coordinator.state.responseEpoch == request.epoch;
}
