import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/ai_runtime.dart';
import 'package:naviwealth/core/ai/runtime/device/device_system_prompt.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';
import 'package:naviwealth/features/ai_chat/data/runtime_routing_api_client.dart';

void main() {
  test('chat applies the shared context policy by default', () async {
    final agent = _CapturingChatAgent();
    final client = RuntimeRoutingAiChatApiClient(agent: agent);

    await client
        .chat(
          session: _session,
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Explain'),
          ],
        )
        .toList();

    final policy = agent.request.contextPolicy;
    expect(policy, isNotNull);
    expect(policy!.maxInputTokens, kDefaultChatMaxInputTokens);
    expect(policy.reserveOutputTokens, kDefaultLlmMaxOutputTokens);
    expect(policy.preserveRecentMessages, kDefaultChatPreserveRecentMessages);
  });

  test('chat preserves an explicitly supplied context policy', () async {
    final agent = _CapturingChatAgent();
    final client = RuntimeRoutingAiChatApiClient(agent: agent);
    const policy = AgentRuntimeContextPolicy(
      maxInputTokens: 32000,
      reserveOutputTokens: 2048,
      preserveRecentMessages: 8,
    );

    await client
        .chat(
          session: _session,
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Explain'),
          ],
          contextPolicy: policy,
        )
        .toList();

    expect(agent.request.contextPolicy, same(policy));
  });
}

final AuthSession _session = AuthSession(
  accessToken: '',
  userId: 'user-1',
  deviceId: 'device-1',
  expiresAt: DateTime.utc(2100),
);

class _CapturingChatAgent implements ChatAgent {
  late ChatAgentTurnRequest request;

  @override
  Stream<AiChatEvent> runTurn(ChatAgentTurnRequest request) async* {
    this.request = request;
    yield const DoneEvent(stopReason: 'end_turn', rounds: 1);
  }
}
