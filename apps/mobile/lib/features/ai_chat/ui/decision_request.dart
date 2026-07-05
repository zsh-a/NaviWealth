/// Typed view over an `ask_user` tool result — the structured decision
/// the model emits when it hits a high-impact / ambiguous fork instead of
/// guessing or burying options in prose (Claude-Code / Codex style).
///
/// Wire shape (produced by `AskUserTool`):
/// ```jsonc
/// {
///   "type": "decision_request",
///   "title": "状态管理方案选择",
///   "context": "本地优先 + 可同步 + AI 可读写的复杂状态。",
///   "options": [
///     { "id": "riverpod", "label": "Riverpod + Drift",
///       "description": "…", "pros": ["…"], "cons": ["…"],
///       "recommended": true }
///   ],
///   "allow_custom": true
/// }
/// ```
/// This is the structured replacement for the old markdown-menu string
/// parsing: the Host renders [DecisionCard] from this, the agent loop
/// pauses, and the user's pick is written back as the next turn.
library;

class DecisionRequest {
  const DecisionRequest({
    required this.title,
    required this.context,
    required this.options,
    required this.allowCustom,
  });

  final String title;
  final String context;
  final List<DecisionOption> options;
  final bool allowCustom;

  /// Best-effort parse of an `ask_user` tool `output`. Returns null for
  /// anything that isn't a well-formed decision request (≥ 2 options).
  static DecisionRequest? tryParse(Object? output) {
    if (output is! Map) return null;
    final m = output.map((k, v) => MapEntry(k.toString(), v));
    if (m['type'] != 'decision_request') return null;
    final title = (m['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;
    final raw = m['options'];
    if (raw is! List) return null;
    final options = <DecisionOption>[];
    for (final o in raw) {
      final opt = DecisionOption.tryParse(o);
      if (opt != null) options.add(opt);
    }
    if (options.length < 2) return null;
    return DecisionRequest(
      title: title,
      context: (m['context'] as String?)?.trim() ?? '',
      options: options,
      allowCustom: m['allow_custom'] == true,
    );
  }
}

class DecisionOption {
  const DecisionOption({
    required this.id,
    required this.label,
    this.description = '',
    this.pros = const <String>[],
    this.cons = const <String>[],
    this.recommended = false,
  });

  final String id;
  final String label;
  final String description;
  final List<String> pros;
  final List<String> cons;
  final bool recommended;

  static DecisionOption? tryParse(Object? o) {
    if (o is! Map) return null;
    final m = o.map((k, v) => MapEntry(k.toString(), v));
    final label = (m['label'] as String?)?.trim();
    if (label == null || label.isEmpty) return null;
    return DecisionOption(
      id: (m['id'] as String?)?.trim().isNotEmpty == true
          ? (m['id'] as String).trim()
          : label,
      label: label,
      description: (m['description'] as String?)?.trim() ?? '',
      pros: _stringList(m['pros']),
      cons: _stringList(m['cons']),
      recommended: m['recommended'] == true,
    );
  }

  static List<String> _stringList(Object? v) => v is List
      ? v
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
      : const <String>[];
}

class DecisionSelectionRequest {
  const DecisionSelectionRequest({
    required this.messageId,
    required this.toolInvocationId,
    required this.option,
    required this.reply,
  });

  final String messageId;
  final String toolInvocationId;
  final DecisionOption option;
  final String reply;
}
