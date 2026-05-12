import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ai_chat/data/sse_parser.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_events.dart';

Stream<List<int>> _stream(List<String> chunks) async* {
  for (final c in chunks) {
    yield utf8.encode(c);
  }
}

Stream<Uint8List> _uint8Stream(List<String> chunks) async* {
  for (final c in chunks) {
    yield Uint8List.fromList(utf8.encode(c));
  }
}

String _frame(String event, Map<String, Object?> payload) =>
    'event: $event\ndata: ${jsonEncode(payload)}\n\n';

void main() {
  group('decodeSseEvents', () {
    test(
      'decodes a typical text → tool_call → tool_result → done sequence',
      () async {
        final source = _stream([
          _frame('text', {'text': 'Hello '}),
          _frame('text', {'text': 'world'}),
          _frame('tool_call', {
            'id': 'call_1',
            'name': 'get_holdings',
            'input': {'as_of': '2026-04-30'},
          }),
          _frame('tool_result', <String, Object?>{
            'id': 'call_1',
            'name': 'get_holdings',
            'output': <String, Object?>{'rows': <Object?>[]},
          }),
          _frame('done', {'stop_reason': 'end_turn', 'rounds': 2}),
        ]);

        final events = await decodeSseEvents(source).toList();
        expect(events, hasLength(5));
        expect(events[0], isA<TextEvent>());
        expect((events[0] as TextEvent).text, 'Hello ');
        expect(events[2], isA<ToolCallEvent>());
        expect((events[2] as ToolCallEvent).name, 'get_holdings');
        expect(events[3], isA<ToolResultEvent>());
        expect(events[4], isA<DoneEvent>());
        final done = events[4] as DoneEvent;
        expect(done.stopReason, 'end_turn');
        expect(done.rounds, 2);
      },
    );

    test('decodes v2 token, thinking, tool, usage, and stop events', () async {
      final source = _stream([
        _frame('thinking_delta', {'text': 'Checking holdings.'}),
        _frame('text_delta', {'text': 'I found '}),
        _frame('tool_call_start', {'id': 'call_1', 'name': 'get_holdings'}),
        _frame('tool_call_delta', {
          'id': 'call_1',
          'partial_input_json': '{"as_of"',
        }),
        _frame('tool_call_end', {
          'id': 'call_1',
          'input': {'as_of': '2026-04-30'},
        }),
        _frame('tool_result', <String, Object?>{
          'id': 'call_1',
          'name': 'get_holdings',
          'output': <String, Object?>{'rows': <Object?>[]},
        }),
        _frame('usage', {
          'input': 10,
          'output': 5,
          'cache_read': 2,
          'cache_write': 1,
        }),
        _frame('stop', {'reason': 'end_turn', 'rounds': 1}),
      ]);

      final events = await decodeSseEvents(source).toList();
      expect(events, hasLength(8));
      expect((events[0] as ThinkingDeltaEvent).text, 'Checking holdings.');
      expect((events[1] as TextEvent).text, 'I found ');
      expect((events[2] as ToolCallStartEvent).name, 'get_holdings');
      expect((events[3] as ToolCallDeltaEvent).partialInputJson, '{"as_of"');
      expect((events[4] as ToolCallEvent).input, {'as_of': '2026-04-30'});
      expect((events[6] as UsageEvent).usage.total, 18);
      expect((events[7] as DoneEvent).stopReason, 'end_turn');
    });

    test('handles frames split across chunk boundaries', () async {
      final whole =
          _frame('text', {'text': '中文测试'}) +
          _frame('done', {'stop_reason': 'end_turn', 'rounds': 1});
      // Slice mid-character intentionally — utf8.decoder is wired to
      // tolerate this.
      final mid = whole.length ~/ 2;
      final source = _stream([whole.substring(0, mid), whole.substring(mid)]);

      final events = await decodeSseEvents(source).toList();
      expect(events.whereType<TextEvent>().single.text, '中文测试');
      expect(events.whereType<DoneEvent>().single.stopReason, 'end_turn');
    });

    test('accepts Dio native Uint8List response streams', () async {
      final source = _uint8Stream([
        _frame('text', {'text': 'stream ok'}),
        _frame('done', {'stop_reason': 'end_turn', 'rounds': 1}),
      ]);

      final events = await decodeSseEvents(source).toList();
      expect(events.whereType<TextEvent>().single.text, 'stream ok');
      expect(events.whereType<DoneEvent>().single.rounds, 1);
    });

    test('skips comment lines and unknown event types', () async {
      final source = _stream([
        ': keep-alive\n',
        _frame('mystery_event', {'foo': 'bar'}),
        _frame('text', {'text': 'after'}),
      ]);
      final events = await decodeSseEvents(source).toList();
      expect(events, hasLength(1));
      expect((events[0] as TextEvent).text, 'after');
    });

    test('drops malformed JSON without breaking subsequent frames', () async {
      // Hand-built so the parser sees a frame whose payload isn't JSON.
      const malformed = 'event: text\ndata: not-json\n\n';
      final source = _stream([
        malformed,
        _frame('text', {'text': 'survived'}),
      ]);
      final events = await decodeSseEvents(source).toList();
      expect(events, hasLength(1));
      expect((events.single as TextEvent).text, 'survived');
    });

    test('emits ErrorEvent followed by DoneEvent for failure stream', () async {
      final source = _stream([
        _frame('error', {'message': 'rate limited'}),
        _frame('done', {'stop_reason': 'error', 'rounds': 0}),
      ]);
      final events = await decodeSseEvents(source).toList();
      expect(events, hasLength(2));
      expect((events[0] as ErrorEvent).message, 'rate limited');
      expect((events[1] as DoneEvent).stopReason, 'error');
    });

    test('flushes a trailing frame missing the blank-line terminator', () async {
      // Some chunked HTTP closes drop the final \n\n. The parser yields
      // the frame on stream close so we don't lose the `done` event.
      final partial =
          'event: done\ndata: ${jsonEncode({'stop_reason': 'end_turn', 'rounds': 1})}\n';
      final source = _stream([partial]);
      final events = await decodeSseEvents(source).toList();
      expect(events.single, isA<DoneEvent>());
    });
  });
}
