/// Structured summary of the persisted chat prefix omitted from the current
/// model context.
///
/// A checkpoint is a local cache with explicit source provenance. It is not a
/// user-authored memory and must always be injected as untrusted context data.
library;

const int kConversationCheckpointVersion = 1;

final class ConversationTurnDigest {
  const ConversationTurnDigest({
    required this.messageId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String messageId;
  final String role;
  final String content;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'message_id': messageId,
    'role': role,
    'content': content,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory ConversationTurnDigest.fromJson(Map<String, Object?> json) {
    return ConversationTurnDigest(
      messageId: json['message_id'] as String? ?? '',
      role: json['role'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

final class ConversationCheckpointSummary {
  const ConversationCheckpointSummary({
    required this.topic,
    this.verifiedFacts = const <String>[],
    this.decisions = const <String>[],
    this.rejectedOptions = const <String>[],
    this.openLoops = const <String>[],
    this.entities = const <String>[],
    this.timeAnchors = const <String>[],
    this.turnDigest = const <ConversationTurnDigest>[],
  });

  final String topic;
  final List<String> verifiedFacts;
  final List<String> decisions;
  final List<String> rejectedOptions;
  final List<String> openLoops;
  final List<String> entities;
  final List<String> timeAnchors;
  final List<ConversationTurnDigest> turnDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'topic': topic,
    'verified_facts': verifiedFacts,
    'decisions': decisions,
    'rejected_options': rejectedOptions,
    'open_loops': openLoops,
    'entities': entities,
    'time_anchors': timeAnchors,
    'turn_digest': turnDigest.map((turn) => turn.toJson()).toList(),
  };

  factory ConversationCheckpointSummary.fromJson(Map<String, Object?> json) {
    final rawDigest = json['turn_digest'];
    return ConversationCheckpointSummary(
      topic: json['topic'] as String? ?? '',
      verifiedFacts: _stringList(json['verified_facts']),
      decisions: _stringList(json['decisions']),
      rejectedOptions: _stringList(json['rejected_options']),
      openLoops: _stringList(json['open_loops']),
      entities: _stringList(json['entities']),
      timeAnchors: _stringList(json['time_anchors']),
      turnDigest: rawDigest is List
          ? rawDigest
                .whereType<Map<Object?, Object?>>()
                .map(
                  (value) => ConversationTurnDigest.fromJson(
                    value.map((key, item) => MapEntry('$key', item)),
                  ),
                )
                .toList(growable: false)
          : const <ConversationTurnDigest>[],
    );
  }
}

final class ConversationCheckpoint {
  const ConversationCheckpoint({
    required this.sessionId,
    required this.ownerUserId,
    required this.summaryThroughMessageId,
    required this.summaryThroughCreatedAt,
    required this.sourceFingerprint,
    required this.sourceMessageCount,
    required this.summary,
    required this.createdAt,
    required this.updatedAt,
    this.version = kConversationCheckpointVersion,
  });

  final String sessionId;
  final String ownerUserId;
  final String summaryThroughMessageId;
  final DateTime summaryThroughCreatedAt;
  final String sourceFingerprint;
  final int sourceMessageCount;
  final ConversationCheckpointSummary summary;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  /// Content passed to Agent Runtime as a `compaction_summary` block.
  Map<String, Object?> toContextJson() => <String, Object?>{
    'checkpoint_version': version,
    'summary_through_message_id': summaryThroughMessageId,
    'summary_through_created_at': summaryThroughCreatedAt
        .toUtc()
        .toIso8601String(),
    'source_message_count': sourceMessageCount,
    ...summary.toJson(),
  };
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}
