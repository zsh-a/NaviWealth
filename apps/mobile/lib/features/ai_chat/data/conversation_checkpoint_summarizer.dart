import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/chat_models.dart';
import '../domain/conversation_checkpoint.dart';

final class ConversationCheckpointSummaryRequest {
  const ConversationCheckpointSummaryRequest({
    required this.sessionId,
    required this.ownerUserId,
    required this.messages,
    this.previous,
  });

  final String sessionId;
  final String ownerUserId;
  final List<ChatMessage> messages;
  final ConversationCheckpoint? previous;
}

/// Host seam for replacing the deterministic fallback with a device LLM
/// summarizer later. The repository, not the summarizer, owns provenance,
/// source fingerprints, and persistence.
abstract interface class ConversationCheckpointSummarizer {
  Future<ConversationCheckpointSummary> summarize(
    ConversationCheckpointSummaryRequest request,
  );
}

/// Loss-bounded, non-generative fallback used even when no LLM is available.
///
/// It quotes source turns and completed tool results instead of inferring new
/// facts. This makes the checkpoint useful offline and prevents a summarizer
/// failure from breaking chat.
final class DeterministicConversationCheckpointSummarizer
    implements ConversationCheckpointSummarizer {
  const DeterministicConversationCheckpointSummarizer();

  @override
  Future<ConversationCheckpointSummary> summarize(
    ConversationCheckpointSummaryRequest request,
  ) async {
    final messages = request.messages;
    if (messages.isEmpty) {
      return const ConversationCheckpointSummary(topic: '');
    }

    var topicSource = messages.first;
    for (final message in messages) {
      if (message.role == ChatRole.user && message.content.trim().isNotEmpty) {
        topicSource = message;
        break;
      }
    }
    final topic = _truncate(topicSource.content.trim(), 240);

    final verifiedFacts = <String>[];
    final decisions = <String>[];
    final openLoops = <String>[];
    final entities = <String>{};
    final timeAnchors = <String>{};

    for (final message in messages) {
      _collectTimeAnchors(message.content, timeAnchors);
      for (final tool in message.toolCalls) {
        _collectEntities(tool.input, entities);
        _collectEntities(tool.output, entities);
        _collectTimeAnchors(_safeJson(tool.input), timeAnchors);
        _collectTimeAnchors(_safeJson(tool.output), timeAnchors);

        if (tool.status == ToolInvocationStatus.completed &&
            tool.output != null &&
            tool.name != 'ask_user' &&
            !tool.name.startsWith('propose_')) {
          verifiedFacts.add(
            '${tool.name}: ${_truncate(_safeJson(tool.output), 600)}',
          );
        }

        final selection = tool.decisionSelection;
        if (selection != null) {
          final title = _decisionTitle(tool.output);
          decisions.add(
            [
              if (title.isNotEmpty) title,
              'selected ${selection.optionId}: ${selection.label}',
              if (selection.reply.trim().isNotEmpty)
                'user reply: ${selection.reply.trim()}',
            ].join(' — '),
          );
        } else if (tool.name == 'ask_user') {
          final title = _decisionTitle(tool.output);
          if (title.isNotEmpty) {
            openLoops.add('Awaiting user decision: $title');
          }
        }
      }
    }

    ChatMessage? lastDialogueMessage;
    for (final message in messages.reversed) {
      if (message.role == ChatRole.user || message.role == ChatRole.assistant) {
        lastDialogueMessage = message;
        break;
      }
    }
    if (lastDialogueMessage?.role == ChatRole.user &&
        lastDialogueMessage!.content.trim().isNotEmpty) {
      openLoops.add(
        'Unanswered user turn: ${_truncate(lastDialogueMessage.content.trim(), 320)}',
      );
    }

    final representative = _representativeMessages(messages);
    final turnDigest = <ConversationTurnDigest>[
      for (final item in representative)
        if (item is ChatMessage)
          ConversationTurnDigest(
            messageId: item.id,
            role: item.role.wire,
            content: _truncate(_messageEvidence(item), 360),
            createdAt: item.createdAt,
          )
        else
          ConversationTurnDigest(
            messageId: 'omitted:${item as int}',
            role: 'checkpoint_metadata',
            content: '$item intermediate source messages omitted from digest',
            createdAt: messages.first.createdAt,
          ),
    ];

    return ConversationCheckpointSummary(
      topic: topic,
      verifiedFacts: _boundedUnique(verifiedFacts, 16),
      decisions: _boundedUnique(decisions, 16),
      // A deterministic renderer cannot safely infer that an unselected
      // option was explicitly rejected. Leave this empty until the source
      // contains an explicit rejection or a richer summarizer proves it.
      rejectedOptions: const <String>[],
      openLoops: _boundedUnique(openLoops, 12),
      entities: _sortedBounded(entities, 32),
      timeAnchors: _sortedBounded(timeAnchors, 32),
      turnDigest: turnDigest,
    );
  }
}

String conversationCheckpointFingerprint(List<ChatMessage> messages) {
  final canonical = <Object?>[
    for (final message in messages)
      <String, Object?>{
        'id': message.id,
        'role': message.role.wire,
        'content': message.content,
        'status': message.status.wire,
        'created_at': message.createdAt.toUtc().toIso8601String(),
        'tool_calls': [
          for (final tool in message.toolCalls) _canonicalize(tool.toJson()),
        ],
      },
  ];
  final encoded = jsonEncode(_canonicalize(canonical));
  return 'sha256:${sha256.convert(utf8.encode(encoded))}';
}

List<Object> _representativeMessages(List<ChatMessage> messages) {
  const firstCount = 8;
  const recentCount = 24;
  if (messages.length <= firstCount + recentCount) {
    return List<Object>.of(messages, growable: false);
  }
  final omitted = messages.length - firstCount - recentCount;
  return <Object>[
    ...messages.take(firstCount),
    omitted,
    ...messages.skip(messages.length - recentCount),
  ];
}

String _messageEvidence(ChatMessage message) {
  final pieces = <String>[];
  if (message.content.trim().isNotEmpty) {
    pieces.add(message.content.trim());
  }
  for (final tool in message.toolCalls) {
    final selection = tool.decisionSelection;
    if (selection != null) {
      pieces.add(
        'decision ${selection.optionId}: ${selection.label}; ${selection.reply}',
      );
    }
  }
  return pieces.join('\n');
}

String _decisionTitle(Object? output) {
  if (output is! Map) return '';
  final title = output['title'];
  return title is String ? title.trim() : '';
}

void _collectEntities(Object? value, Set<String> entities, {String? key}) {
  if (entities.length >= 32) return;
  if (value is Map) {
    for (final entry in value.entries) {
      _collectEntities(entry.value, entities, key: '${entry.key}');
    }
    return;
  }
  if (value is Iterable) {
    for (final item in value) {
      _collectEntities(item, entities, key: key);
    }
    return;
  }
  if (value is! String || key == null) return;
  final normalizedKey = key.toLowerCase();
  final entityKey =
      normalizedKey == 'id' ||
      normalizedKey.endsWith('_id') ||
      normalizedKey.contains('entity') ||
      normalizedKey.contains('symbol') ||
      normalizedKey.contains('ticker');
  final trimmed = value.trim();
  if (entityKey && trimmed.isNotEmpty && trimmed.length <= 160) {
    entities.add('$key:$trimmed');
  }
}

void _collectTimeAnchors(String value, Set<String> anchors) {
  if (anchors.length >= 32 || value.isEmpty) return;
  final patterns = <RegExp>[
    RegExp(r'\b20\d{2}-\d{1,2}-\d{1,2}(?:T[0-9:.+\-Z]+)?\b'),
    RegExp(r'20\d{2}年\d{1,2}月\d{1,2}日'),
  ];
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(value)) {
      final anchor = match.group(0);
      if (anchor != null) anchors.add(anchor);
      if (anchors.length >= 32) return;
    }
  }
}

List<String> _boundedUnique(List<String> values, int limit) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in values.reversed) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) continue;
    result.add(trimmed);
    if (result.length == limit) break;
  }
  return result.reversed.toList(growable: false);
}

List<String> _sortedBounded(Set<String> values, int limit) {
  final sorted = values.toList()..sort();
  return sorted.take(limit).toList(growable: false);
}

String _safeJson(Object? value) {
  try {
    return jsonEncode(_canonicalize(value));
  } on Object {
    return '$value';
  }
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map((entry) => MapEntry('${entry.key}', entry.value))
            .toList()
          ..sort((left, right) => left.key.compareTo(right.key));
    return <String, Object?>{
      for (final entry in entries) entry.key: _canonicalize(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  return '$value';
}

String _truncate(String value, int maxRunes) {
  final runes = value.runes.toList(growable: false);
  if (runes.length <= maxRunes) return value;
  return '${String.fromCharCodes(runes.take(maxRunes))}…';
}
