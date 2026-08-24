import '../contracts/interaction.dart';
import '../intent/ai_intent_invocation.dart';
import 'delivery_ledger.dart';
import 'interaction_ids.dart';

enum InteractionSessionStatus { active, closed }

enum InteractionInputLane {
  idle,
  listening,
  speechDetected,
  endpointing,
  committed,
}

enum InteractionExecutionLane {
  idle,
  running,
  toolRunning,
  waitingInteraction,
  done,
}

enum InteractionOutputLane { idle, synthesizing, playing, paused, interrupted }

enum BargeInPhase { none, candidate, committed, falseInterruption }

enum InteractionInputOrigin { voice, touch, keyboard, watch, image, system }

extension InteractionInputOriginWire on InteractionInputOrigin {
  String get wire => name;
}

/// Complete immutable state for one modality-agnostic interaction session.
///
/// The state intentionally keeps input, execution, and output as orthogonal
/// lanes. For example, input may be [speechDetected] while execution is
/// [toolRunning] and output is [playing].
final class InteractionState {
  InteractionState._({
    required this.sessionId,
    required this.status,
    required this.inputLane,
    required this.executionLane,
    required this.outputLane,
    required this.responseEpoch,
    required this.sequence,
    required this.transcript,
    required this.generatedText,
    required this.deliveryLedger,
    required this.bargeInPhase,
    required this.invocation,
    this.activeTurnId,
    this.executingTurnId,
    this.inputOrigin,
    this.activeOperationId,
    this.pendingInteraction,
    this.candidateStartedAt,
    this.lastContextProjection,
    this.lastCommittedText,
    this.lastCommittedOrigin,
    this.lastInteractionResponse,
  });

  factory InteractionState.initial({
    required SessionId sessionId,
    AiIntentInvocation? invocation,
  }) => InteractionState._(
    sessionId: sessionId,
    status: InteractionSessionStatus.active,
    inputLane: InteractionInputLane.idle,
    executionLane: InteractionExecutionLane.idle,
    outputLane: InteractionOutputLane.idle,
    responseEpoch: const ResponseEpoch.initial(),
    sequence: 0,
    transcript: '',
    generatedText: '',
    deliveryLedger: DeliveryLedger.empty(),
    bargeInPhase: BargeInPhase.none,
    invocation: invocation,
  );

  final SessionId sessionId;
  final InteractionSessionStatus status;
  final InteractionInputLane inputLane;
  final InteractionExecutionLane executionLane;
  final InteractionOutputLane outputLane;
  final ResponseEpoch responseEpoch;

  /// Last sequence accepted by the reducer. It is allocated by the host
  /// Coordinator, never by an individual ASR/TTS/Agent producer.
  final int sequence;

  final TurnId? activeTurnId;
  final TurnId? executingTurnId;
  final InteractionInputOrigin? inputOrigin;
  final OperationId? activeOperationId;
  final AiInteractionEnvelope? pendingInteraction;

  /// Current draft transcript. It is not durable Memory and is not a domain
  /// write until a caller explicitly commits a turn.
  final String transcript;

  /// Complete generated assistant text for the current response. It is
  /// separate from [deliveryLedger] and [lastContextProjection].
  final String generatedText;
  final DeliveryLedger deliveryLedger;

  final BargeInPhase bargeInPhase;
  final DateTime? candidateStartedAt;
  final ContextProjection? lastContextProjection;

  final AiIntentInvocation? invocation;
  final String? lastCommittedText;
  final InteractionInputOrigin? lastCommittedOrigin;
  final AiInteractionResponse? lastInteractionResponse;

  bool get isClosed => status == InteractionSessionStatus.closed;

  InteractionState copyWith({
    InteractionSessionStatus? status,
    InteractionInputLane? inputLane,
    InteractionExecutionLane? executionLane,
    InteractionOutputLane? outputLane,
    ResponseEpoch? responseEpoch,
    int? sequence,
    Object? activeTurnId = _unset,
    Object? executingTurnId = _unset,
    Object? inputOrigin = _unset,
    Object? activeOperationId = _unset,
    Object? pendingInteraction = _unset,
    String? transcript,
    String? generatedText,
    DeliveryLedger? deliveryLedger,
    BargeInPhase? bargeInPhase,
    Object? candidateStartedAt = _unset,
    Object? lastContextProjection = _unset,
    Object? lastCommittedText = _unset,
    Object? lastCommittedOrigin = _unset,
    Object? lastInteractionResponse = _unset,
  }) => InteractionState._(
    sessionId: sessionId,
    status: status ?? this.status,
    inputLane: inputLane ?? this.inputLane,
    executionLane: executionLane ?? this.executionLane,
    outputLane: outputLane ?? this.outputLane,
    responseEpoch: responseEpoch ?? this.responseEpoch,
    sequence: sequence ?? this.sequence,
    activeTurnId: _optional<TurnId>(activeTurnId, this.activeTurnId),
    executingTurnId: _optional<TurnId>(executingTurnId, this.executingTurnId),
    inputOrigin: _optional<InteractionInputOrigin>(
      inputOrigin,
      this.inputOrigin,
    ),
    activeOperationId: _optional<OperationId>(
      activeOperationId,
      this.activeOperationId,
    ),
    pendingInteraction: _optional<AiInteractionEnvelope>(
      pendingInteraction,
      this.pendingInteraction,
    ),
    transcript: transcript ?? this.transcript,
    generatedText: generatedText ?? this.generatedText,
    deliveryLedger: deliveryLedger ?? this.deliveryLedger,
    bargeInPhase: bargeInPhase ?? this.bargeInPhase,
    candidateStartedAt: _optional<DateTime>(
      candidateStartedAt,
      this.candidateStartedAt,
    ),
    lastContextProjection: _optional<ContextProjection>(
      lastContextProjection,
      this.lastContextProjection,
    ),
    invocation: invocation,
    lastCommittedText: _optional<String>(
      lastCommittedText,
      this.lastCommittedText,
    ),
    lastCommittedOrigin: _optional<InteractionInputOrigin>(
      lastCommittedOrigin,
      this.lastCommittedOrigin,
    ),
    lastInteractionResponse: _optional<AiInteractionResponse>(
      lastInteractionResponse,
      this.lastInteractionResponse,
    ),
  );

  static const Object _unset = Object();

  static T? _optional<T>(Object? value, T? current) =>
      identical(value, _unset) ? current : value as T?;
}
