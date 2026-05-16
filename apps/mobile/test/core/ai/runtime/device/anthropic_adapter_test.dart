import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_client.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_sse_decoder.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/llm_stream_event.dart';

List<LlmStreamEvent> _mapAll(String sse) {
  final state = AnthropicStreamState();
  final out = <LlmStreamEvent>[];
  // Split exactly like the backend `sse_data_frames`: blank-line frames,
  // join `data:` lines.
  for (final frame in sse.split('\n\n')) {
    final data = frame
        .split('\n')
        .where((l) => l.startsWith('data: '))
        .map((l) => l.substring(6))
        .join('\n');
    if (data.trim().isEmpty) continue;
    out.addAll(mapAnthropicFrame(state, data));
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
  group('mapAnthropicFrame — ported from event_map.rs', () {
    test('maps text delta (empty start block + text_delta)', () {
      final events = _mapAll(
        'event: content_block_start\n'
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n'
        'event: content_block_delta\n'
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello"}}\n\n',
      );
      expect(events, hasLength(1));
      expect((events.single as LlmTextDelta).text, 'hello');
    });

    test('maps tool_use start / delta / stop with assembled input', () {
      final events = _mapAll(
        'data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"get_risk_alerts","input":{}}}\n\n'
        'data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"as_of\\":"}}\n\n'
        'data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\\"2026-05-07\\"}"}}\n\n'
        'data: {"type":"content_block_stop","index":1}\n\n',
      );
      expect(events, hasLength(4));
      final start = events[0] as LlmToolCallStart;
      expect(start.id, 'toolu_1');
      expect(start.name, 'get_risk_alerts');
      expect((events[1] as LlmToolCallDelta).partialInputJson, '{"as_of":');
      expect((events[2] as LlmToolCallDelta).partialInputJson, '"2026-05-07"}');
      final end = events[3] as LlmToolCallEnd;
      expect(end.id, 'toolu_1');
      expect(end.name, 'get_risk_alerts');
      expect(end.input, {'as_of': '2026-05-07'});
    });

    test('maps usage from message_start and message_delta', () {
      final events = _mapAll(
        'data: {"type":"message_start","message":{"usage":{"input_tokens":11,"output_tokens":1,"cache_read_input_tokens":2,"cache_creation_input_tokens":3}}}\n\n'
        'data: {"type":"message_delta","usage":{"output_tokens":7}}\n\n',
      );
      expect(events, hasLength(2));
      final a = events[0] as LlmUsage;
      expect([a.inputTokens, a.outputTokens, a.cacheReadTokens, a.cacheWriteTokens], [11, 1, 2, 3]);
      final b = events[1] as LlmUsage;
      expect([b.inputTokens, b.outputTokens, b.cacheReadTokens, b.cacheWriteTokens], [0, 7, 0, 0]);
    });

    test('maps message_delta stop_reason', () {
      final events = _mapAll(
        'data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}\n\n',
      );
      expect(events, hasLength(1));
      expect((events.single as LlmMessageStop).reason, LlmStopReason.toolUse);
    });

    test('unknown stop_reason yields no stop event (parity with backend)', () {
      expect(
        _mapAll('data: {"type":"message_delta","delta":{"stop_reason":"weird"}}\n\n'),
        isEmpty,
      );
    });

    test('error frame maps to LlmStreamErrorEvent', () {
      final events = _mapAll(
        'data: {"type":"error","error":{"type":"overloaded_error","message":"busy"}}\n\n',
      );
      final e = events.single as LlmStreamErrorEvent;
      expect(e.code, 'overloaded_error');
      expect(e.message, 'busy');
    });

    test('[DONE], ping, message_stop and malformed frames are skipped', () {
      final state = AnthropicStreamState();
      expect(mapAnthropicFrame(state, '[DONE]'), isEmpty);
      expect(mapAnthropicFrame(state, '   '), isEmpty);
      expect(mapAnthropicFrame(state, '{"type":"ping"}'), isEmpty);
      expect(mapAnthropicFrame(state, '{"type":"message_stop"}'), isEmpty);
      expect(mapAnthropicFrame(state, 'not json'), isEmpty); // divergence: skip
    });

    test('tool input falls back to start-block input when no delta', () {
      final events = _mapAll(
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"n","input":{"k":1}}}\n\n'
        'data: {"type":"content_block_stop","index":0}\n\n',
      );
      expect((events[1] as LlmToolCallEnd).input, {'k': 1});
    });
  });

  group('decodeAnthropicSse — streaming, chunk-boundary tolerant', () {
    test('reassembles frames split across byte chunks', () async {
      const sse =
          'event: content_block_start\n'
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你好世界"}}\n\n'
          'event: message_delta\n'
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n';
      final events = await decodeAnthropicSse(_chunked(sse, size: 5)).toList();
      expect(events.whereType<LlmTextDelta>().single.text, '你好世界');
      expect(events.whereType<LlmMessageStop>().single.reason,
          LlmStopReason.endTurn);
    });

    test('skips `:` keepalive comment lines', () async {
      const sse = ':keepalive\n\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"x"}}\n\n';
      final events = await decodeAnthropicSse(_chunked(sse)).toList();
      expect(events.single, isA<LlmTextDelta>());
    });
  });

  group('LlmConfig.messagesUrl — ported from client.rs', () {
    test('default base resolves to /v1/messages', () {
      expect(
        LlmConfig(apiKey: 'k', model: 'm').messagesUrl(),
        'https://api.anthropic.com/v1/messages',
      );
    });

    test('honours /v1, exact /messages and trailing slashes', () {
      expect(
        LlmConfig(apiKey: 'k', baseUrl: 'https://x.test/v1', model: 'm')
            .messagesUrl(),
        'https://x.test/v1/messages',
      );
      expect(
        LlmConfig(
                apiKey: 'k',
                baseUrl: 'https://x.test/custom/messages',
                model: 'm')
            .messagesUrl(),
        'https://x.test/custom/messages',
      );
      expect(
        LlmConfig(apiKey: 'k', baseUrl: 'https://x.test///', model: 'm')
            .messagesUrl(),
        'https://x.test/v1/messages',
      );
    });

    test('fromCredentials carries key + custom base url', () {
      final c = LlmConfig.fromCredentials(
        const LlmCredentials(
          provider: LlmProvider.anthropic,
          apiKey: 'sk-ant',
          baseUrl: 'https://gw.test/v1',
        ),
      );
      expect(c.apiKey, 'sk-ant');
      expect(c.messagesUrl(), 'https://gw.test/v1/messages');
      expect(c.model, kDefaultDeviceModel);
    });
  });

  group('wire types', () {
    test('auth headers send both x-api-key and bearer', () {
      final h = llmAuthHeaders('sk-ant');
      expect(h['x-api-key'], 'sk-ant');
      expect(h['authorization'], 'Bearer sk-ant');
      expect(h['anthropic-version'], '2023-06-01');
      expect(h['content-type'], 'application/json');
    });

    test('request forces stream true/false for the two call shapes', () {
      final req = AnthropicRequest(
        model: 'claude-x',
        maxTokens: 256,
        system: 'sys',
        messages: [AnthropicChatMessage.text('user', 'hi')],
        tools: const [
          AnthropicToolSchema(
            name: 'get_x',
            description: 'd',
            inputSchema: {'type': 'object'},
          ),
        ],
        stream: false,
      );
      final streaming =
          jsonDecode(req.encodeStreaming()) as Map<String, Object?>;
      final oneShot =
          jsonDecode(req.encodeOneShot()) as Map<String, Object?>;
      expect(streaming['stream'], true);
      expect(oneShot['stream'], false);
      final msg0 =
          (streaming['messages']! as List).first as Map<String, Object?>;
      expect(msg0['content'], 'hi');
      final tool0 =
          (streaming['tools']! as List).first as Map<String, Object?>;
      expect(tool0['input_schema'], {'type': 'object'});
      expect(streaming['max_tokens'], 256);
    });

    test('content-block builders match Anthropic shapes', () {
      expect(AnthropicBlocks.text('a'), {'type': 'text', 'text': 'a'});
      expect(
        AnthropicBlocks.toolResult(toolUseId: 't', content: 'r', isError: true),
        {
          'type': 'tool_result',
          'tool_use_id': 't',
          'content': 'r',
          'is_error': true,
        },
      );
      expect(
        AnthropicBlocks.imageBase64(mediaType: 'image/png', data: 'AAAA'),
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': 'image/png',
            'data': 'AAAA',
          },
        },
      );
    });
  });
}
