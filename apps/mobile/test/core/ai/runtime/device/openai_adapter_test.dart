import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/llm_stream_event.dart';
import 'package:naviwealth/core/ai/runtime/device/openai/openai_client.dart';
import 'package:naviwealth/core/ai/runtime/device/openai/openai_sse_decoder.dart';

List<LlmStreamEvent> _mapAll(String sse) {
  final state = OpenAiStreamState();
  final out = <LlmStreamEvent>[];
  for (final frame in sse.split('\n\n')) {
    final data = frame
        .split('\n')
        .where((l) => l.startsWith('data: '))
        .map((l) => l.substring(6))
        .join('\n');
    if (data.trim().isEmpty) continue;
    out.addAll(mapOpenAiFrame(state, data));
  }
  return out;
}

Stream<List<int>> _chunked(String s, {int size = 7}) async* {
  final bytes = utf8.encode(s);
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
  }
}

void main() {
  group('OpenAiConfig', () {
    test('default base resolves to /v1/chat/completions', () {
      expect(
        OpenAiConfig(apiKey: 'k', model: 'm').chatCompletionsUrl(),
        'https://api.openai.com/v1/chat/completions',
      );
    });

    test('honours /v1, exact endpoint and trailing slashes', () {
      expect(
        OpenAiConfig(
          apiKey: 'k',
          baseUrl: 'https://x.test/v1',
          model: 'm',
        ).chatCompletionsUrl(),
        'https://x.test/v1/chat/completions',
      );
      expect(
        OpenAiConfig(
          apiKey: 'k',
          baseUrl: 'https://x.test/custom/chat/completions',
          model: 'm',
        ).chatCompletionsUrl(),
        'https://x.test/custom/chat/completions',
      );
      expect(
        OpenAiConfig(
          apiKey: 'k',
          baseUrl: 'https://x.test///',
          model: 'm',
        ).chatCompletionsUrl(),
        'https://x.test/v1/chat/completions',
      );
    });

    test('fromProfile carries OpenAI defaults and model override', () {
      final c = OpenAiConfig.fromProfile(
        const LlmProfile(
          id: 'p',
          name: '',
          provider: LlmProvider.openai,
          apiKey: 'sk',
          baseUrl: 'https://gw.test/v1',
        ),
      );
      expect(c.apiKey, 'sk');
      expect(c.chatCompletionsUrl(), 'https://gw.test/v1/chat/completions');
      expect(c.model, kDefaultOpenAiDeviceModel);
    });
  });

  group('OpenAI payload conversion', () {
    test('maps Anthropic-shaped session to Chat Completions', () {
      final req = AnthropicRequest(
        model: 'gpt-x',
        maxTokens: 128,
        system: 'sys',
        messages: [
          AnthropicChatMessage.text('user', 'hi'),
          AnthropicChatMessage(
            role: 'assistant',
            content: [
              AnthropicBlocks.text('checking'),
              {
                'type': 'tool_use',
                'id': 'call_1',
                'name': 'get_net_worth',
                'input': {'currency': 'CNY'},
              },
            ],
          ),
          AnthropicChatMessage(
            role: 'user',
            content: [
              AnthropicBlocks.toolResult(
                toolUseId: 'call_1',
                content: '{"ok":true}',
              ),
            ],
          ),
        ],
        tools: const [
          AnthropicToolSchema(
            name: 'get_net_worth',
            description: 'd',
            inputSchema: {'type': 'object'},
          ),
        ],
        stream: true,
      );

      final payload = openAiChatCompletionsPayload(req, stream: true);
      final messages = payload['messages']! as List;
      expect(messages[0], {'role': 'system', 'content': 'sys'});
      expect(messages[1], {'role': 'user', 'content': 'hi'});
      final assistant = messages[2] as Map;
      expect(assistant['role'], 'assistant');
      expect(assistant['content'], 'checking');
      expect(assistant['tool_calls'], hasLength(1));
      expect(messages[3], {
        'role': 'tool',
        'tool_call_id': 'call_1',
        'content': '{"ok":true}',
      });
      expect(payload['tools'], hasLength(1));
      expect(payload['stream_options'], {'include_usage': true});
    });

    test('assistant thinking block re-serialises as reasoning_content', () {
      final req = AnthropicRequest(
        model: 'mimo',
        maxTokens: 128,
        system: '',
        messages: [
          AnthropicChatMessage.text('user', 'hi'),
          AnthropicChatMessage(
            role: 'assistant',
            content: [
              AnthropicBlocks.thinking(thinking: 'reasoned through it'),
              AnthropicBlocks.text('working'),
              {
                'type': 'tool_use',
                'id': 'call_1',
                'name': 'get_net_worth',
                'input': const <String, Object?>{},
              },
            ],
          ),
        ],
        tools: const [],
        stream: true,
      );

      final payload = openAiChatCompletionsPayload(req, stream: true);
      final assistant = (payload['messages']! as List)[1] as Map;
      expect(assistant['role'], 'assistant');
      expect(assistant['content'], 'working');
      expect(assistant['reasoning_content'], 'reasoned through it');
      expect(assistant['tool_calls'], hasLength(1));
    });

    test('no thinking block ⇒ no reasoning_content key', () {
      final req = AnthropicRequest(
        model: 'gpt-x',
        maxTokens: 64,
        system: '',
        messages: [
          AnthropicChatMessage(
            role: 'assistant',
            content: [AnthropicBlocks.text('plain')],
          ),
        ],
        tools: const [],
        stream: false,
      );
      final assistant =
          (openAiChatCompletionsPayload(req, stream: false)['messages']!
              as List)[0] as Map;
      expect(assistant.containsKey('reasoning_content'), isFalse);
    });
  });

  group('mapOpenAiFrame', () {
    test('maps text delta and stop reason', () {
      final events = _mapAll(
        'data: {"choices":[{"delta":{"content":"hello"},"finish_reason":null}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n',
      );
      expect((events[0] as LlmTextDelta).text, 'hello');
      expect((events[1] as LlmMessageStop).reason, LlmStopReason.endTurn);
    });

    test('maps tool call deltas and finish reason', () {
      final events = _mapAll(
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"get_holdings","arguments":"{\\""}}]},"finish_reason":null}]}\n\n'
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"currency\\":\\"CNY\\"}"}}]},"finish_reason":null}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n\n',
      );
      expect(events[0], isA<LlmToolCallStart>());
      expect((events[0] as LlmToolCallStart).name, 'get_holdings');
      expect(events.whereType<LlmToolCallDelta>(), hasLength(2));
      final end = events.whereType<LlmToolCallEnd>().single;
      expect(end.id, 'call_1');
      expect(end.input, {'currency': 'CNY'});
      expect(events.last, isA<LlmMessageStop>());
      expect((events.last as LlmMessageStop).reason, LlmStopReason.toolUse);
    });

    test('maps usage-only stream chunk', () {
      final events = _mapAll(
        'data: {"choices":[],"usage":{"prompt_tokens":11,"completion_tokens":7}}\n\n',
      );
      final u = events.single as LlmUsage;
      expect([u.inputTokens, u.outputTokens], [11, 7]);
    });

    test('decodes chunk-boundary SSE', () async {
      const sse =
          'data: {"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n';
      final events = await decodeOpenAiSse(_chunked(sse, size: 5)).toList();
      expect(events.whereType<LlmTextDelta>().single.text, '你好');
      expect(
        events.whereType<LlmMessageStop>().single.reason,
        LlmStopReason.maxTokens,
      );
    });
  });

  group('wire helpers', () {
    test('auth headers send bearer only', () {
      final h = openAiAuthHeaders('sk');
      expect(h['authorization'], 'Bearer sk');
      expect(h['content-type'], 'application/json');
      expect(h.containsKey('x-api-key'), isFalse);
    });
  });
}
