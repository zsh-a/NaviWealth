import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_runner.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/trace/agent_runtime_trace_recorder.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';

void main() {
  test('records profile turns into AiTrace spans', () async {
    final traces = <AiTrace>[];
    final recorder = AgentRuntimeTraceRecorder(
      appendTrace: (trace) async => traces.add(trace),
    );
    final trace = await recorder.recordProfileTurn(
      agentId: 'execution_review',
      domain: kDomainExecution,
      surface: 'settings_runtime_check',
      startedAt: DateTime.utc(2026, 6, 29, 8),
      finishedAt: DateTime.utc(2026, 6, 29, 8, 0, 1),
      result: _result(),
    );

    expect(traces.single, same(trace));
    expect(trace.requestId, 'agent-runtime:execution_review:run_1');
    expect(trace.backend, Backend.device);
    expect(trace.routingReason, kFrbAgentRuntimeProfileRoutingReason);
    expect(trace.intent.domain, kDomainExecution);
    expect(trace.terminalReason, TerminalReason.done);
    expect(trace.spans.map((span) => span.name), <String>[
      'turn',
      'llm:profile',
      'tool:read_task',
    ]);
    expect(
      trace.toolSpans.single.attributes,
      containsPair('response_id', 'call_1'),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('surface', 'settings_runtime_check'),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('dispatched_effect_count', 1),
    );
  });

  test('marks budget exhaustion as closed early', () async {
    final recorder = AgentRuntimeTraceRecorder(appendTrace: (_) async {});
    final trace = await recorder.recordProfileTurn(
      agentId: 'execution_review',
      startedAt: DateTime.utc(2026, 6, 29, 8),
      finishedAt: DateTime.utc(2026, 6, 29, 8),
      requestId: 'trace_custom',
      result: _result(
        stepRun: const AgentRuntimeNativeStepRunResult(
          terminalStep: <String, Object?>{'status': 'failed'},
          dispatchedEffectCount: 0,
          budgetExhausted: true,
        ),
      ),
    );

    expect(trace.requestId, 'trace_custom');
    expect(trace.terminalReason, TerminalReason.closedEarly);
    expect(trace.spans.first.status, AiSpanStatus.error);
    expect(
      trace.spans.first.attributes,
      containsPair('budget_exhausted', true),
    );
  });

  test('uses native terminal reason for failed runs', () async {
    final recorder = AgentRuntimeTraceRecorder(appendTrace: (_) async {});
    final trace = await recorder.recordStepRun(
      agentId: 'execution_review',
      startedAt: DateTime.utc(2026, 6, 29, 8),
      finishedAt: DateTime.utc(2026, 6, 29, 8),
      stepRun: const AgentRuntimeNativeStepRunResult(
        terminalStep: <String, Object?>{
          'run_id': 'run_failed',
          'status': 'failed',
          'run_state': <String, Object?>{
            'status': 'failed',
            'step_index': 1,
            'remaining_effect_count': 0,
            'effect_result_count': 1,
            'terminal_reason': 'stream_error',
          },
        },
        dispatchedEffectCount: 1,
      ),
    );

    expect(trace.terminalReason, TerminalReason.streamError);
    expect(trace.spans.first.status, AiSpanStatus.error);
    expect(
      trace.spans.first.attributes,
      containsPair('native_terminal_reason', 'stream_error'),
    );
  });

  test(
    'uses FRB trace event run state when root run state is absent',
    () async {
      final recorder = AgentRuntimeTraceRecorder(appendTrace: (_) async {});
      final trace = await recorder.recordStepRun(
        agentId: 'execution_review',
        startedAt: DateTime.utc(2026, 6, 29, 8),
        finishedAt: DateTime.utc(2026, 6, 29, 8),
        stepRun: const AgentRuntimeNativeStepRunResult(
          terminalStep: <String, Object?>{
            'run_id': 'run_trace_event_state',
            'status': 'failed',
            'trace_event': <String, Object?>{
              'kind': 'agent_runtime_step',
              'status': 'failed',
              'tool_name': 'read_task',
              'run_state': <String, Object?>{
                'status': 'failed',
                'step_index': 2,
                'remaining_effect_count': 0,
                'effect_result_count': 2,
                'terminal_reason': 'stream_error',
              },
            },
          },
          dispatchedEffectCount: 2,
        ),
      );

      expect(trace.terminalReason, TerminalReason.streamError);
      expect(
        trace.spans.first.attributes,
        containsPair('native_step_index', 2),
      );
      expect(
        trace.spans.first.attributes,
        containsPair('native_effect_result_count', 2),
      );
      expect(
        trace.spans.first.attributes,
        containsPair('native_terminal_reason', 'stream_error'),
      );
      expect(
        trace.spans.first.attributes,
        containsPair('native_trace_event_kind', 'agent_runtime_step'),
      );
      expect(
        trace.spans.first.attributes,
        containsPair('native_trace_event_status', 'failed'),
      );
      expect(
        trace.spans.first.attributes,
        containsPair('native_trace_event_tool_name', 'read_task'),
      );
    },
  );

  test('records native step-only effect loop runs', () async {
    final traces = <AiTrace>[];
    final recorder = AgentRuntimeTraceRecorder(
      appendTrace: (trace) async => traces.add(trace),
    );

    final trace = await recorder.recordStepRun(
      agentId: 'knowledge_routine_due',
      domain: kDomainKnowledge,
      surface: 'knowledge_routine_due',
      startedAt: DateTime.utc(2026, 6, 29, 8),
      finishedAt: DateTime.utc(2026, 6, 29, 8, 0, 1),
      stepRun: const AgentRuntimeNativeStepRunResult(
        terminalStep: <String, Object?>{
          'run_id': 'run_2',
          'status': 'completed',
          'run_state': <String, Object?>{
            'status': 'completed',
            'step_index': 4,
            'remaining_effect_count': 0,
            'effect_result_count': 1,
            'terminal_reason': 'done',
          },
        },
        dispatchedEffectCount: 1,
        nativeTraceEvents: <Map<String, Object?>>[
          <String, Object?>{
            'kind': 'agent_runtime_step',
            'status': 'completed',
            'step_index': 3,
            'tool_name': 'list_due_routines',
            'run_state': <String, Object?>{
              'status': 'effect_requested',
              'step_index': 3,
              'remaining_effect_count': 0,
              'effect_result_count': 0,
              'terminal_reason': null,
            },
          },
        ],
        steps: <Map<String, Object?>>[
          <String, Object?>{
            'run_id': 'run_2',
            'step_index': 3,
            'status': 'effect_requested',
            'effect': <String, Object?>{
              'kind': 'tool',
              'effect_id': 'call_1',
              'name': 'list_due_routines',
              'input': <String, Object?>{'limit': 50},
            },
          },
          <String, Object?>{'run_id': 'run_2', 'status': 'completed'},
        ],
        effectResponses: <Map<String, Object?>>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'call_1',
            'result': <String, Object?>{'routines': <Object?>[]},
          },
        ],
      ),
    );

    expect(traces.single, same(trace));
    expect(trace.requestId, 'agent-runtime:knowledge_routine_due:run_2');
    expect(trace.routingReason, kFrbNativeEffectLoopRoutingReason);
    expect(trace.intent.label, 'agent_runtime_step_run');
    expect(trace.llmRoundCount, 0);
    expect(trace.toolSpans.single.id, 'tool:4');
    expect(trace.toolSpans.single.name, 'tool:list_due_routines');
    expect(
      trace.toolSpans.single.attributes,
      containsPair('native_step_index', 3),
    );
    expect(
      trace.toolSpans.single.attributes,
      containsPair('native_trace_event_kind', 'agent_runtime_step'),
    );
    expect(
      trace.toolSpans.single.attributes,
      containsPair('native_trace_event_status', 'completed'),
    );
    expect(
      trace.toolSpans.single.attributes,
      containsPair('native_trace_event_tool_name', 'list_due_routines'),
    );
    expect(
      trace.toolSpans.single.attributes,
      containsPair('native_trace_event_step_index', 3),
    );
    expect(
      trace.toolSpans.single.attributes,
      containsPair('native_trace_event_remaining_effect_count', 0),
    );
    expect(
      trace.toolSpans.single.attributes,
      containsPair('native_trace_event_effect_result_count', 0),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('surface', 'knowledge_routine_due'),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('native_trace_event_count', 1),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('native_trace_event_status', 'completed'),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('native_trace_event_tool_name', 'list_due_routines'),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('native_effect_result_count', 1),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('native_terminal_reason', 'done'),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('native_remaining_effect_count', 0),
    );
    expect(trace.spans.first.attributes, containsPair('native_step_index', 4));
  });

  test(
    'aligns effect responses by host-effect ordinal, not native step index',
    () async {
      final recorder = AgentRuntimeTraceRecorder(appendTrace: (_) async {});

      final trace = await recorder.recordStepRun(
        agentId: 'knowledge_review',
        startedAt: DateTime.utc(2026, 6, 29, 8),
        finishedAt: DateTime.utc(2026, 6, 29, 8, 0, 1),
        stepRun: const AgentRuntimeNativeStepRunResult(
          terminalStep: <String, Object?>{
            'run_id': 'run_multi',
            'status': 'completed',
          },
          dispatchedEffectCount: 2,
          steps: <Map<String, Object?>>[
            <String, Object?>{
              'run_id': 'run_multi',
              'step_index': 0,
              'status': 'effect_requested',
              'effect': <String, Object?>{
                'kind': 'tool',
                'effect_id': 'call_1',
                'name': 'list_due_reviews',
              },
            },
            <String, Object?>{
              'run_id': 'run_multi',
              'step_index': 1,
              'status': 'completed',
            },
            <String, Object?>{
              'run_id': 'run_multi',
              'step_index': 2,
              'status': 'effect_requested',
              'effect': <String, Object?>{
                'kind': 'tool',
                'effect_id': 'call_2',
                'name': 'list_open_assumptions',
              },
            },
            <String, Object?>{
              'run_id': 'run_multi',
              'step_index': 3,
              'status': 'completed',
            },
          ],
          effectResponses: <Map<String, Object?>>[
            <String, Object?>{'jsonrpc': '2.0', 'id': 'call_1'},
            <String, Object?>{'jsonrpc': '2.0', 'id': 'call_2'},
          ],
        ),
      );

      final spans = trace.toolSpans.toList(growable: false);
      expect(spans, hasLength(2));
      expect(spans.first.attributes, containsPair('response_id', 'call_1'));
      expect(spans.last.attributes, containsPair('response_id', 'call_2'));
    },
  );

  test('records profile completions without native steps', () async {
    final traces = <AiTrace>[];
    final recorder = AgentRuntimeTraceRecorder(
      appendTrace: (trace) async => traces.add(trace),
    );

    final trace = await recorder.recordProfileCompletion(
      agentId: 'knowledge_inbox_triage',
      domain: kDomainKnowledge,
      surface: 'knowledge_inbox_triage',
      startedAt: DateTime.utc(2026, 6, 29, 8),
      finishedAt: DateTime.utc(2026, 6, 29, 8, 0, 1),
      requestId: 'profile_completion_1',
      llmResponse: const <String, Object?>{
        'provider': 'openai',
        'model': 'gpt-test',
        'finish_reason': 'stop',
        'usage': <String, Object?>{'input_tokens': 11, 'output_tokens': 7},
      },
    );

    expect(traces.single, same(trace));
    expect(trace.requestId, 'profile_completion_1');
    expect(trace.routingReason, kFrbAgentRuntimeProfileRoutingReason);
    expect(trace.intent.label, 'agent_runtime_profile_completion');
    expect(trace.intent.domain, kDomainKnowledge);
    expect(trace.terminalReason, TerminalReason.done);
    expect(trace.spans.map((span) => span.name), <String>[
      'turn',
      'llm:profile',
    ]);
    expect(trace.llmSpans.single.model, 'gpt-test');
    expect(trace.llmSpans.single.tokens?.input, 11);
    expect(trace.llmSpans.single.tokens?.output, 7);
    expect(
      trace.spans.first.attributes,
      containsPair('surface', 'knowledge_inbox_triage'),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('terminal_status', 'completed'),
    );
  });

  test('records errored profile completions', () async {
    final recorder = AgentRuntimeTraceRecorder(appendTrace: (_) async {});

    final trace = await recorder.recordProfileCompletion(
      agentId: 'knowledge_contradiction',
      domain: kDomainKnowledge,
      surface: 'knowledge_contradiction',
      startedAt: DateTime.utc(2026, 6, 29, 8),
      finishedAt: DateTime.utc(2026, 6, 29, 8, 0, 1),
      llmResponse: null,
      error: StateError('native unavailable'),
    );

    expect(trace.terminalReason, TerminalReason.streamError);
    expect(trace.spans.first.status, AiSpanStatus.error);
    expect(trace.llmSpans.single.status, AiSpanStatus.error);
    expect(trace.llmSpans.single.errorCode, 'StateError');
    expect(
      trace.spans.first.attributes,
      containsPair('terminal_status', 'failed'),
    );
  });

  test(
    'records vision profile completions with ingest routing reason',
    () async {
      final recorder = AgentRuntimeTraceRecorder(appendTrace: (_) async {});

      final trace = await recorder.recordProfileCompletion(
        agentId: 'finance_vision_ingest',
        domain: kDomainFinance,
        surface: 'finance_vision_ingest',
        routingReason: kFrbVisionIngestRoutingReason,
        startedAt: DateTime.utc(2026, 6, 29, 8),
        finishedAt: DateTime.utc(2026, 6, 29, 8, 0, 1),
        llmResponse: const <String, Object?>{
          'provider': 'anthropic',
          'model': 'claude-test',
          'finish_reason': 'tool_use',
        },
      );

      expect(trace.routingReason, kFrbVisionIngestRoutingReason);
      expect(trace.intent.domain, kDomainFinance);
      expect(trace.llmSpans.single.model, 'claude-test');
      expect(
        trace.llmSpans.single.attributes,
        containsPair('provider', 'anthropic'),
      );
    },
  );
}

AgentRuntimeProfileTurnResult _result({
  AgentRuntimeNativeStepRunResult? stepRun,
}) {
  final run =
      stepRun ??
      const AgentRuntimeNativeStepRunResult(
        terminalStep: <String, Object?>{
          'run_id': 'run_1',
          'status': 'completed',
          'output': <String, Object?>{'ok': true},
        },
        dispatchedEffectCount: 1,
        steps: <Map<String, Object?>>[
          <String, Object?>{
            'run_id': 'run_1',
            'status': 'effect_requested',
            'effect': <String, Object?>{
              'kind': 'tool',
              'effect_id': 'call_1',
              'name': 'read_task',
              'input': <String, Object?>{'id': 'task_1'},
            },
          },
          <String, Object?>{'run_id': 'run_1', 'status': 'completed'},
        ],
        effectResponses: <Map<String, Object?>>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'call_1',
            'result': <String, Object?>{'ok': true},
          },
        ],
      );
  return AgentRuntimeProfileTurnResult(
    llmResponse: const <String, Object?>{
      'provider': 'openai',
      'model': 'gpt-test',
      'finish_reason': 'stop',
      'content': 'done',
    },
    step: run.terminalStep,
    stepRun: run,
  );
}
