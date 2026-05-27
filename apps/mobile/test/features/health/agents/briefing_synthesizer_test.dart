// D-2.5b BriefingSynthesizer tests.
//
// Two surfaces:
//   * ProgrammaticBriefingSynthesizer — pin the deterministic
//     summarisation behaviour. Mirrors the existing static-synthesise
//     coverage in `morning_briefing_agent_test.dart` so a refactor to
//     the agent can't silently regress the line shapes.
//   * LlmBriefingSynthesizer — wraps a DeviceLlmClient. We fake the
//     client to script the happy path and several failure modes;
//     every failure must fall back to the programmatic baseline.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_client.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/llm_stream_event.dart';
import 'package:naviwealth/features/health/agents/briefing_synthesizer.dart';
import 'package:naviwealth/features/health/data/health_metric_memory_indexer.dart';

EventRecord _sleepEvent({
  required DateTime when,
  required double valueSeconds,
  Set<String> entities = const {},
}) => EventRecord(
  id: 'sleep-${when.toIso8601String()}',
  type: kEventSleepSessionEnded,
  timestamp: when,
  source: kHealthSource,
  ownerUserId: 'u-test',
  title: 'sleep',
  summary: 'sleep',
  payload: <String, Object?>{'value': valueSeconds, 'unit': 's'},
  entities: entities,
  importance: 0.5,
);

EventRecord _hrvEvent({
  required DateTime when,
  required double valueMs,
}) => EventRecord(
  id: 'hrv-${when.toIso8601String()}',
  type: kEventHrvRecorded,
  timestamp: when,
  source: kHealthSource,
  ownerUserId: 'u-test',
  title: 'hrv',
  summary: 'hrv',
  payload: <String, Object?>{'value': valueMs, 'unit': 'ms'},
  entities: const <String>{},
  importance: 0.55,
);

EventRecord _financeEvent({
  required DateTime when,
  required String type,
}) => EventRecord(
  id: 'fin-${type}-${when.toIso8601String()}',
  type: type,
  timestamp: when,
  source: 'options_trade_journal',
  ownerUserId: 'u-test',
  title: type,
  summary: type,
  payload: const <String, Object?>{},
  entities: const <String>{},
  importance: 0.5,
);

class _FakeLlmConfig implements DeviceLlmConfig {
  const _FakeLlmConfig({this.model = 'fake-model'});
  @override
  final String model;
}

class _FakeLlmClient implements DeviceLlmClient {
  _FakeLlmClient({this.scriptedText, this.shouldThrow = false});
  final String? scriptedText;
  final bool shouldThrow;
  int completeCalls = 0;

  @override
  DeviceLlmConfig get config => const _FakeLlmConfig();

  @override
  Future<AnthropicCompletion> complete(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) async {
    completeCalls++;
    if (shouldThrow) {
      throw const LlmRequestException(statusCode: 500, message: 'boom');
    }
    final text = scriptedText;
    if (text == null) {
      return const AnthropicCompletion(content: <Object?>[]);
    }
    return AnthropicCompletion(
      content: <Object?>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
    );
  }

  @override
  Stream<LlmStreamEvent> streamMessages(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) async* {
    throw UnsupportedError('streamMessages not used by briefing synthesizer');
  }
}

void main() {
  group('ProgrammaticBriefingSynthesizer', () {
    const synth = ProgrammaticBriefingSynthesizer();
    final now = DateTime.utc(2026, 5, 27, 7);

    test('returns empty output when there is no usable signal', () async {
      final out = await synth.synthesize(
        BriefingInputs(
          dayKey: '2026-05-27',
          healthEvents: const <EventRecord>[],
          financeEvents: const <EventRecord>[],
        ),
      );
      expect(out.isEmpty, isTrue);
      expect(out.source, BriefingSource.programmatic);
    });

    test('composes sleep + HRV + finance into a single line', () async {
      final out = await synth.synthesize(
        BriefingInputs(
          dayKey: '2026-05-27',
          healthEvents: <EventRecord>[
            _sleepEvent(when: now, valueSeconds: 7.5 * 3600),
            _hrvEvent(when: now, valueMs: 48),
          ],
          financeEvents: <EventRecord>[
            _financeEvent(when: now, type: 'trade_opened'),
            _financeEvent(when: now, type: 'trade_opened'),
            _financeEvent(when: now, type: 'dividend_received'),
          ],
        ),
      );
      expect(out.summary, 'Slept 7.5h · HRV 48ms · Finance: 2 trade opened, 1 dividend received');
      expect(out.sleepLine, 'Slept 7.5h');
      expect(out.hrvLine, 'HRV 48ms');
      expect(out.financeLine, 'Finance: 2 trade opened, 1 dividend received');
      expect(out.source, BriefingSource.programmatic);
    });

    test('tags short / long sleep from entities', () async {
      final out = await synth.synthesize(
        BriefingInputs(
          dayKey: '2026-05-27',
          healthEvents: <EventRecord>[
            _sleepEvent(
              when: now,
              valueSeconds: 4.3 * 3600,
              entities: const {'short_sleep'},
            ),
          ],
          financeEvents: const <EventRecord>[],
        ),
      );
      expect(out.summary, 'Slept 4.3h (short)');
    });
  });

  group('LlmBriefingSynthesizer', () {
    final now = DateTime.utc(2026, 5, 27, 7);
    final baselineInputs = BriefingInputs(
      dayKey: '2026-05-27',
      healthEvents: <EventRecord>[
        _sleepEvent(when: now, valueSeconds: 7.5 * 3600),
        _hrvEvent(when: now, valueMs: 48),
      ],
      financeEvents: const <EventRecord>[],
    );

    test('uses LLM output when the call succeeds', () async {
      final client = _FakeLlmClient(
        scriptedText: 'You slept 7.5h with HRV 48ms — calm baseline morning.',
      );
      final synth = LlmBriefingSynthesizer(client: client);
      final out = await synth.synthesize(baselineInputs);
      expect(out.source, BriefingSource.llm);
      expect(out.summary, contains('7.5h'));
      // Structured lines are still surfaced — agent embeds them in the
      // memory `outcome` payload regardless of source.
      expect(out.sleepLine, 'Slept 7.5h');
      expect(out.hrvLine, 'HRV 48ms');
      expect(client.completeCalls, 1);
    });

    test('falls back to programmatic when the LLM call throws', () async {
      final client = _FakeLlmClient(shouldThrow: true);
      final synth = LlmBriefingSynthesizer(client: client);
      final out = await synth.synthesize(baselineInputs);
      expect(out.source, BriefingSource.programmatic);
      expect(out.summary, 'Slept 7.5h · HRV 48ms');
    });

    test('falls back when the LLM returns empty content', () async {
      final client = _FakeLlmClient(scriptedText: null);
      final synth = LlmBriefingSynthesizer(client: client);
      final out = await synth.synthesize(baselineInputs);
      expect(out.source, BriefingSource.programmatic);
      expect(out.summary, 'Slept 7.5h · HRV 48ms');
    });

    test('skips the LLM call when baseline already empty', () async {
      final client = _FakeLlmClient(scriptedText: 'something');
      final synth = LlmBriefingSynthesizer(client: client);
      final out = await synth.synthesize(
        BriefingInputs(
          dayKey: '2026-05-27',
          healthEvents: const <EventRecord>[],
          financeEvents: const <EventRecord>[],
        ),
      );
      expect(out.isEmpty, isTrue);
      expect(client.completeCalls, 0);
    });
  });
}
