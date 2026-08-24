/// Provider-neutral identifiers used by the InteractionSession reducer.
///
/// These wrappers deliberately stay smaller than the durable Agent Runtime
/// identifiers. They make it difficult to accidentally compare a turn id to
/// a response epoch while keeping the session state serialisable and host
/// friendly.
library;

final class SessionId {
  const SessionId(this.value);

  final String value;

  bool get isValid => value.trim().isNotEmpty;

  @override
  bool operator ==(Object other) => other is SessionId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class TurnId {
  const TurnId(this.value);

  final String value;

  bool get isValid => value.trim().isNotEmpty;

  @override
  bool operator ==(Object other) => other is TurnId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class OperationId {
  const OperationId(this.value);

  final String value;

  bool get isValid => value.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is OperationId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class ResponseEpoch {
  const ResponseEpoch(this.value);

  const ResponseEpoch.initial() : value = 0;

  final int value;

  ResponseEpoch next() => ResponseEpoch(value + 1);

  @override
  bool operator ==(Object other) =>
      other is ResponseEpoch && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'epoch:$value';
}

/// The ordering stamp assigned by the session Coordinator when an event
/// enters the reducer. ASR, Agent, and playback producers never allocate the
/// global sequence themselves.
final class InteractionStamp {
  const InteractionStamp({
    required this.sessionId,
    required this.epoch,
    required this.sequence,
    this.turnId,
    this.operationId,
  });

  final SessionId sessionId;
  final TurnId? turnId;
  final ResponseEpoch epoch;
  final int sequence;
  final OperationId? operationId;

  Map<String, Object?> toJson() => <String, Object?>{
    'session_id': sessionId.value,
    if (turnId != null) 'turn_id': turnId!.value,
    'response_epoch': epoch.value,
    'sequence': sequence,
    if (operationId != null) 'operation_id': operationId!.value,
  };
}
