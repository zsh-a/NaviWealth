import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/frb_chat_runner.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';

void main() {
  test('maps FRB profile completion into chat events', () async {
    final bridge = _FakeLlmBridge(
      response: const <String, Object?>{
        'protocol_version': 'agent.v1',
        'provider': 'openai',
        'model': 'gpt-test',
        'content': 'FRB answer',
        'finish_reason': 'stop',
        'usage': <String, Object?>{
          'input_tokens': 7,
          'output_tokens': 3,
          'total_tokens': 10,
        },
      },
    );
    final runner = FrbChatRunner(llmBridge: bridge);

    final events = await runner
        .run(
          messages: const <WireMessage>[
            WireMessage(role: 'user', content: 'Hello'),
          ],
          model: 'requested-model',
        )
        .toList();

    expect(events, hasLength(3));
    expect((events[0] as UsageEvent).usage.input, 7);
    expect((events[0] as UsageEvent).usage.output, 3);
    expect((events[1] as TextEvent).text, 'FRB answer');
    final done = events[2] as DoneEvent;
    expect(done.stopReason, 'end_turn');
    expect(done.rounds, 1);
    expect(bridge.messages.single, <String, Object?>{
      'role': 'user',
      'content': 'Hello',
    });
    expect(bridge.metadata['agent_id'], kFrbChatRunnerAgentId);
    expect(bridge.metadata['surface'], 'ai_chat');
    expect(bridge.metadata['requested_model'], 'requested-model');
    expect(bridge.metadata['streaming'], false);
  });

  test('maps native finish reasons to chat stop reasons', () async {
    final cases = <String, String>{
      'length': 'max_tokens',
      'tool_call': 'tool_use',
      'content_filter': 'refusal',
      'error': 'error',
    };

    for (final entry in cases.entries) {
      final runner = FrbChatRunner(
        llmBridge: _FakeLlmBridge(
          response: <String, Object?>{
            'content': '',
            'finish_reason': entry.key,
          },
        ),
      );

      final events = await runner
          .run(
            messages: const <WireMessage>[
              WireMessage(role: 'user', content: 'Hello'),
            ],
          )
          .toList();

      expect((events.single as DoneEvent).stopReason, entry.value);
    }
  });

  test(
    'emits existing chat error vocabulary when FRB completion fails',
    () async {
      final runner = FrbChatRunner(
        llmBridge: _FakeLlmBridge(error: StateError('native unavailable')),
      );

      final events = await runner
          .run(
            messages: const <WireMessage>[
              WireMessage(role: 'user', content: 'Hello'),
            ],
          )
          .toList();

      expect(events, hasLength(2));
      expect((events[0] as ErrorEvent).code, 'frb_chat_error');
      expect((events[1] as DoneEvent).stopReason, 'error');
    },
  );
}

class _FakeLlmBridge implements AgentRuntimeLlmBridge {
  _FakeLlmBridge({
    this.response = const <String, Object?>{
      'content': 'ok',
      'finish_reason': 'stop',
    },
    this.error,
  });

  final Map<String, Object?> response;
  final Object? error;
  List<Map<String, Object?>> messages = const <Map<String, Object?>>[];
  Map<String, Object?> metadata = const <String, Object?>{};

  @override
  Map<String, Object?> buildRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return <String, Object?>{
      'messages': messages,
      'tools': tools,
      'metadata': metadata,
    };
  }

  @override
  Future<Map<String, Object?>> completeMock({
    required List<Map<String, Object?>> messages,
    required String responseText,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    this.messages = messages;
    this.metadata = metadata;
    final error = this.error;
    if (error != null) throw error;
    return response;
  }

  @override
  Future<Map<String, Object?>> validateRequest({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    throw UnimplementedError();
  }
}
