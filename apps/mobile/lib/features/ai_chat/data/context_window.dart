import '../domain/chat_models.dart';
import 'ai_chat_api_client.dart';

/// Result of trimming a conversation to fit within the model's context.
class ContextWindow {
  const ContextWindow({required this.wire, required this.droppedTurns});

  /// Messages that should be sent to `POST /ai/chat`.
  final List<WireMessage> wire;

  /// Number of older turns dropped to stay under the budget. The UI
  /// surfaces this to the user as "已折叠 N 条历史" so they know context
  /// was truncated.
  final int droppedTurns;
}

/// Conservative budget: backend caps a single request body at 32 KB
/// (`MAX_REQUEST_BODY_BYTES`). We keep the wire payload comfortably under
/// that to leave room for tool-result blocks the worker injects mid-loop
/// on subsequent rounds. Char count is a coarse proxy for tokens, but
/// safe for Chinese (≈ 1 char ≈ 1.5 tokens for Anthropic's tokenizer)
/// because we underbudget; a precise tiktoken port is overkill for v1.
const int kDefaultContextCharBudget = 18000;

/// Always keep the most recent N turns regardless of budget so the user
/// can finish a thought even if it would push the budget over. Anything
/// older drops first.
const int kMinKeptTurns = 4;

/// Build the wire payload for `/ai/chat` from the persisted [history]
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
  final eligible = <ChatMessage>[];
  for (final m in history) {
    if (m.role != ChatRole.user && m.role != ChatRole.assistant) continue;
    if (m.status != ChatMessageStatus.complete) continue;
    if (m.content.trim().isEmpty) continue;
    eligible.add(m);
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
    kept.add(WireMessage(role: msg.role.wire, content: msg.content));
    used += cost;
    keptCount += 1;
  }

  final wire = <WireMessage>[...kept.reversed, pendingWire];
  final droppedTurns = eligible.length - keptCount;
  return ContextWindow(wire: wire, droppedTurns: droppedTurns);
}
