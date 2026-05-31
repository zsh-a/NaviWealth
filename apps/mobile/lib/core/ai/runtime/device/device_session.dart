/// Per-turn device agent session.
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
    this.basePrompt = kDeviceSystemPromptBase,
  });

  /// Conversation so far. Seeded from the inbound turn; the loop
  /// appends assistant/user turns as tool rounds advance.
  final List<AnthropicChatMessage> messages;

  /// Device-derived portfolio snapshot. Threaded to the tool
  /// dispatcher; unused while tools are stubbed.
  final Map<String, Object?>? portfolioSnapshot;

  /// ContextPack-derived system extension. Appended verbatim
  /// after the base prompt + clock, mirroring the backend.
  final String? systemAppendix;

  /// Pre-assembled base prompt = [kDeviceSystemPromptBase] + active
  /// domain blocks. Built by `assembledSystemPromptProvider`. Tests
  /// that construct a session directly fall back to the base-only
  /// default since they don't exercise domain routing.
  final String basePrompt;

  /// Inner Anthropic round-trips performed this turn.
  int roundsUsed = 0;

  /// Base prompt + current clock + optional appendix. The clock is the
  /// device clock (no server in the path); the prompt tells the model
  /// that the current time is supplied with the message.
  String systemPrompt() {
    final base =
        '$basePrompt\n\n当前时间: ${DateTime.now().toUtc().toIso8601String()}';
    return systemAppendix == null ? base : '$base$systemAppendix';
  }
}
