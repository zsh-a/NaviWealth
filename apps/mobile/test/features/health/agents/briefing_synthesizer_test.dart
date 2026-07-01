// D-2.5b BriefingSynthesizer tests.
//
// Two surfaces:
//   * ProgrammaticBriefingSynthesizer — pin the deterministic
//     summarisation behaviour. Mirrors the existing static-synthesise
//     coverage in `morning_briefing_agent_test.dart` so a refactor to
//     the agent can't silently regress the line shapes.
//   * FrbBriefingSynthesizer — wraps the FRB profile-turn runner. We fake
//     the runner to script the happy path and fallback behavior.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_profile_turn_binding.dart';
import 'package:naviwealth/app/agent_runtime_runner.dart';
import 'package:naviwealth/app/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/features/health/agents/briefing_synthesizer.dart';
import 'package:naviwealth/features/health/data/health_metric_memory_indexer.dart';

import '../../../app/agent_runtime_native_bridge_test_harness.dart';

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

EventRecord _hrvEvent({required DateTime when, required double valueMs}) =>
    EventRecord(
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

EventRecord _financeEvent({required DateTime when, required String type}) =>
    EventRecord(
      id: 'fin-$type-${when.toIso8601String()}',
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

void main() {
  group('ProgrammaticBriefingSynthesizer', () {
    const synth = ProgrammaticBriefingSynthesizer();
    final now = DateTime.utc(2026, 5, 27, 7);

    test('returns empty output when there is no usable signal', () async {
      final out = await synth.synthesize(
        const BriefingInputs(
          dayKey: '2026-05-27',
          healthEvents: <EventRecord>[],
          financeEvents: <EventRecord>[],
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
      expect(
        out.summary,
        'Slept 7.5h · HRV 48ms · Finance: 2 trade opened, 1 dividend received',
      );
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

  group('FrbBriefingSynthesizer', () {
    final now = DateTime.utc(2026, 5, 27, 7);
    final baselineInputs = BriefingInputs(
      dayKey: '2026-05-27',
      healthEvents: <EventRecord>[
        _sleepEvent(when: now, valueSeconds: 7.5 * 3600),
        _hrvEvent(when: now, valueMs: 48),
      ],
      financeEvents: const <EventRecord>[],
    );

    test('runs Morning Briefing through the FRB profile-turn runner', () async {
      final runner = _FakeProfileTurnRunner(
        content: 'You slept 7.5h and HRV was 48ms.',
      );
      final traces = <AgentRuntimeProfileTurnResult>[];
      final synth = FrbBriefingSynthesizer(
        runtime: _profileRuntime(
          runner: runner,
          recordTrace: (result) async => traces.add(result),
        ),
      );
      final out = await synth.synthesize(baselineInputs);

      expect(out.source, BriefingSource.llm);
      expect(out.summary, 'You slept 7.5h and HRV was 48ms.');
      expect(out.sleepLine, 'Slept 7.5h');
      expect(out.hrvLine, 'HRV 48ms');
      expect(runner.calls.single.agentId, 'morning_briefing');
      expect(
        runner.calls.single.metadata,
        containsPair('surface', 'health_morning_briefing'),
      );
      expect(
        runner.calls.single.metadata,
        containsPair('day_key', '2026-05-27'),
      );
      expect(runner.calls.single.maxToolSteps, 0);
      expect(
        runner.calls.single.messages.first,
        containsPair('role', 'system'),
      );
      expect(traces.single.llmResponse['content'], out.summary);
      expect(traces.single.step['status'], 'completed');
    });

    test('falls back when the FRB runner throws', () async {
      final runner = _FakeProfileTurnRunner(shouldThrow: true);
      final synth = FrbBriefingSynthesizer(
        runtime: _profileRuntime(runner: runner),
      );
      final out = await synth.synthesize(baselineInputs);

      expect(out.source, BriefingSource.programmatic);
      expect(out.summary, 'Slept 7.5h · HRV 48ms');
    });

    test(
      'ignores trace recording failures after a successful FRB turn',
      () async {
        final runner = _FakeProfileTurnRunner(
          content: 'You slept 7.5h and HRV was 48ms.',
        );
        final synth = FrbBriefingSynthesizer(
          runtime: _profileRuntime(
            runner: runner,
            recordTrace: (_) async =>
                throw StateError('trace store unavailable'),
          ),
        );

        final out = await synth.synthesize(baselineInputs);

        expect(out.source, BriefingSource.llm);
        expect(out.summary, 'You slept 7.5h and HRV was 48ms.');
        expect(runner.calls.single.agentId, 'morning_briefing');
      },
    );
  });
}

AgentRuntimeProfileTurnBinding _profileRuntime({
  required AgentRuntimeProfileTurnRunner runner,
  Future<void> Function(AgentRuntimeProfileTurnResult result)? recordTrace,
}) {
  return AgentRuntimeProfileTurnBinding(
    agentId: 'morning_briefing',
    domain: 'health',
    surface: 'health_morning_briefing',
    runner: runner,
    recordTrace: recordTrace,
  );
}

class _FakeProfileTurnRunner extends AgentRuntimeProfileTurnRunner {
  _FakeProfileTurnRunner({this.content, this.shouldThrow = false})
    : super(
        catalog: _catalog(),
        llmBridge: _llmBridge(FakeAgentRuntimeNativeBridge()),
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: FakeAgentRuntimeNativeBridge(),
          toolHost: AgentRuntimeToolHost(dispatcher: _NoopDispatcher()),
        ),
      );

  final String? content;
  final bool shouldThrow;
  final calls = <_ProfileTurnCall>[];

  @override
  Future<AgentRuntimeProfileTurnResult> run({
    required String agentId,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxToolSteps,
  }) async {
    calls.add(
      _ProfileTurnCall(
        agentId: agentId,
        messages: messages,
        metadata: metadata,
        maxToolSteps: maxToolSteps,
      ),
    );
    if (shouldThrow) throw StateError('frb failed');
    return AgentRuntimeProfileTurnResult(
      llmResponse: <String, Object?>{
        'protocol_version': 'agent.v1',
        'provider': 'openai',
        'model': 'gpt-test',
        'content': content,
        'finish_reason': 'stop',
      },
      step: const <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': 'run_1',
        'agent_id': 'morning_briefing',
        'status': 'completed',
      },
    );
  }
}

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: DateTime.utc(2026, 6, 29, 8),
    activeDomains: const <String>['health'],
    agents: const <AgentRuntimeAgentSpec>[],
    tools: const <AgentRuntimeToolSpec>[],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

AgentRuntimeLlmBridge _llmBridge(AgentRuntimeNativeBridge bridge) {
  return AgentRuntimeLlmBridge(
    bridge: bridge,
    profile: const LlmProfile(
      id: 'profile_1',
      name: 'Local profile',
      provider: LlmProvider.openai,
      apiKey: 'sk-test',
      model: 'gpt-test',
    ),
  );
}

class _ProfileTurnCall {
  const _ProfileTurnCall({
    required this.agentId,
    required this.messages,
    required this.metadata,
    required this.maxToolSteps,
  });

  final String agentId;
  final List<Map<String, Object?>> messages;
  final Map<String, Object?> metadata;
  final int? maxToolSteps;
}

class _NoopDispatcher implements DeviceToolDispatcher {
  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    return null;
  }
}
