import '../domain/chat_models.dart';
import 'ai_chat_api_client.dart';

/// Result of trimming a conversation to fit within the model's context.
class ContextWindow {
  const ContextWindow({required this.wire, required this.droppedTurns});

  /// Messages that should be sent to the chat runtime.
  final List<WireMessage> wire;

  /// Number of older turns dropped to stay under the budget. The UI
  /// surfaces this to the user as "已折叠 N 条历史" so they know context
  /// was truncated.
  final int droppedTurns;
}

/// Conservative budget for the device runtime prompt. We keep the wire
/// payload comfortably below the retired backend's 32 KB body cap so
/// the same chat history shape remains safe if a relay is reintroduced.
/// Char count is a coarse proxy for tokens, but safe for Chinese
/// (≈ 1 char ≈ 1.5 tokens for Anthropic's tokenizer) because we
/// underbudget.
const int kDefaultContextCharBudget = 18000;

/// Always keep the most recent N turns regardless of budget so the user
/// can finish a thought even if it would push the budget over. Anything
/// older drops first.
const int kMinKeptTurns = 4;

/// Build the wire payload for the chat runtime from persisted [history]
/// plus a freshly-typed [pending] user message.
///
/// Local-only roles (`system`, `error`) and partially-streamed assistant
/// turns (`status != complete`) are skipped — the model doesn't need
/// truncation banners or half-formed prior replies.
ContextWindow buildContextWindow({
  required List<ChatMessage> history,
  required String pending,
  int charBudget = kDefaultContextCharBudget,
  int minKept = kMinKeptTurns,
}) {
  final eligible = <WireMessage>[];
  for (final m in history) {
    if (m.role != ChatRole.user && m.role != ChatRole.assistant) continue;
    if (m.status != ChatMessageStatus.complete) continue;
    final content = _historyContentForRuntime(m);
    if (content == null) continue;
    eligible.add(WireMessage(role: m.role.wire, content: content));
  }

  final pendingWire = WireMessage(role: 'user', content: pending);
  // Walk from newest to oldest until we exceed the budget; then keep the
  // youngest [minKept] regardless. The pending message always ships.
  final reversed = eligible.reversed.toList(growable: false);
  final kept = <WireMessage>[];
  var used = pending.length;
  var keptCount = 0;
  for (final msg in reversed) {
    final cost = msg.content.length;
    final overBudget = used + cost > charBudget;
    if (overBudget && keptCount >= minKept) break;
    kept.add(msg);
    used += cost;
    keptCount += 1;
  }

  final wire = <WireMessage>[...kept.reversed, pendingWire];
  final droppedTurns = eligible.length - keptCount;
  return ContextWindow(wire: wire, droppedTurns: droppedTurns);
}

String? _historyContentForRuntime(ChatMessage message) {
  final text = message.content.trim();
  final toolTranscript = _toolTranscriptForRuntime(message.toolCalls);
  if (text.isEmpty) return toolTranscript;
  if (toolTranscript == null) return text;
  return '$text\n\n$toolTranscript';
}

String? _toolTranscriptForRuntime(List<ToolInvocation> toolCalls) {
  final lines = <String>[];
  for (final tool in toolCalls) {
    if (tool.name != 'ask_user') continue;
    final request = _DecisionTranscript.tryParse(tool.output);
    if (request == null) continue;
    lines.add(request.render(tool.decisionSelection));
  }
  if (lines.isEmpty) return null;
  return lines.join('\n\n');
}

class _DecisionTranscript {
  const _DecisionTranscript({
    required this.title,
    required this.context,
    required this.options,
  });

  final String title;
  final String context;
  final List<_DecisionOptionTranscript> options;

  static _DecisionTranscript? tryParse(Object? output) {
    if (output is! Map) return null;
    final map = output.map((k, v) => MapEntry(k.toString(), v));
    if (map['type'] != 'decision_request') return null;
    final title = (map['title'] as String?)?.trim();
    final rawOptions = map['options'];
    if (title == null || title.isEmpty || rawOptions is! List) return null;
    final options = <_DecisionOptionTranscript>[];
    for (final raw in rawOptions) {
      final option = _DecisionOptionTranscript.tryParse(raw);
      if (option != null) options.add(option);
    }
    if (options.length < 2) return null;
    return _DecisionTranscript(
      title: title,
      context: (map['context'] as String?)?.trim() ?? '',
      options: options,
    );
  }

  String render(DecisionSelection? selection) {
    final buffer = StringBuffer('Decision requested: $title');
    if (context.isNotEmpty) buffer.write('\nContext: $context');
    buffer.write('\nOptions:');
    for (final option in options) {
      buffer.write('\n- ${option.id}: ${option.label}');
      if (option.description.isNotEmpty) {
        buffer.write(' — ${option.description}');
      }
      if (option.recommended) buffer.write(' (recommended)');
    }
    if (selection != null) {
      buffer
        ..write('\nSelected option: ${selection.optionId}')
        ..write(' (${selection.label})')
        ..write('\nUser reply: ${selection.reply}');
    }
    return buffer.toString();
  }
}

class _DecisionOptionTranscript {
  const _DecisionOptionTranscript({
    required this.id,
    required this.label,
    required this.description,
    required this.recommended,
  });

  final String id;
  final String label;
  final String description;
  final bool recommended;

  static _DecisionOptionTranscript? tryParse(Object? output) {
    if (output is! Map) return null;
    final map = output.map((k, v) => MapEntry(k.toString(), v));
    final label = (map['label'] as String?)?.trim();
    if (label == null || label.isEmpty) return null;
    return _DecisionOptionTranscript(
      id: (map['id'] as String?)?.trim().isNotEmpty == true
          ? (map['id'] as String).trim()
          : label,
      label: label,
      description: (map['description'] as String?)?.trim() ?? '',
      recommended: map['recommended'] == true,
    );
  }
}
