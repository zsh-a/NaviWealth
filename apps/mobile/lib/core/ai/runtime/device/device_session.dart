/// Per-turn device agent session (§4.6 W-D3).
///
/// Dart port of `apps/backend/src/ai/runtime/session.rs`. The message
/// list is mutated in place across tool rounds (assistant `tool_use`
/// then user `tool_result`), exactly like the backend loop.
library;

import 'anthropic/anthropic_wire.dart';
import 'device_system_prompt.dart';

class DeviceSession {
  DeviceSession({
    required this.messages,
    this.portfolioSnapshot,
    this.systemAppendix,
  });

  /// Conversation so far. Seeded from the inbound turn; the loop
  /// appends assistant/user turns as tool rounds advance.
  final List<AnthropicChatMessage> messages;

  /// Device-derived portfolio snapshot. Threaded to the tool
  /// dispatcher (W-D4); unused while tools are stubbed.
  final Map<String, Object?>? portfolioSnapshot;

  /// ContextPack-derived system extension (W-D6). Appended verbatim
  /// after the base prompt + clock, mirroring the backend.
  final String? systemAppendix;

  /// Inner Anthropic round-trips performed this turn.
  int roundsUsed = 0;

  /// `SYSTEM_PROMPT` + current clock + optional appendix. The clock is
  /// the device clock here (no server in the path); the prompt tells
  /// the model the current time is supplied with the message.
  String systemPrompt() {
    final base =
        '$kDeviceSystemPrompt\n\n当前时间: ${DateTime.now().toUtc().toIso8601String()}';
    return systemAppendix == null ? base : '$base$systemAppendix';
  }
}
