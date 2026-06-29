import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_runner.dart';
import 'package:naviwealth/app/agent_runtime_trace_recorder.dart';
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
      containsPair('dispatched_tool_count', 1),
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
          dispatchedToolCount: 0,
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
            'remaining_tool_count': 0,
            'tool_result_count': 1,
            'terminal_reason': 'stream_error',
          },
        },
        dispatchedToolCount: 1,
      ),
    );

    expect(trace.terminalReason, TerminalReason.streamError);
    expect(trace.spans.first.status, AiSpanStatus.error);
    expect(
      trace.spans.first.attributes,
      containsPair('native_terminal_reason', 'stream_error'),
    );
  });

  test('records native step-only tool plan runs', () async {
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
            'remaining_tool_count': 0,
            'tool_result_count': 1,
            'terminal_reason': 'done',
          },
        },
        dispatchedToolCount: 1,
        nativeTraceEvents: <Map<String, Object?>>[
          <String, Object?>{'kind': 'agent_runtime_step', 'step_index': 3},
        ],
        steps: <Map<String, Object?>>[
          <String, Object?>{
            'run_id': 'run_2',
            'step_index': 3,
            'status': 'tool_call_requested',
            'tool_call': <String, Object?>{
              'tool_call_id': 'call_1',
              'name': 'list_due_routines',
              'input': <String, Object?>{'limit': 50},
            },
          },
          <String, Object?>{'run_id': 'run_2', 'status': 'completed'},
        ],
        toolResponses: <Map<String, Object?>>[
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
    expect(trace.routingReason, 'frb_native_tool_plan');
    expect(trace.intent.label, 'agent_runtime_step_run');
    expect(trace.llmRoundCount, 0);
    expect(trace.toolSpans.single.id, 'tool:4');
    expect(trace.toolSpans.single.name, 'tool:list_due_routines');
    expect(
      trace.toolSpans.single.attributes,
      containsPair('native_step_index', 3),
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
      containsPair('native_tool_result_count', 1),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('native_terminal_reason', 'done'),
    );
    expect(
      trace.spans.first.attributes,
      containsPair('native_remaining_tool_count', 0),
    );
    expect(trace.spans.first.attributes, containsPair('native_step_index', 4));
  });
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
        dispatchedToolCount: 1,
        steps: <Map<String, Object?>>[
          <String, Object?>{
            'run_id': 'run_1',
            'status': 'tool_call_requested',
            'tool_call': <String, Object?>{
              'tool_call_id': 'call_1',
              'name': 'read_task',
              'input': <String, Object?>{'id': 'task_1'},
            },
          },
          <String, Object?>{'run_id': 'run_1', 'status': 'completed'},
        ],
        toolResponses: <Map<String, Object?>>[
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
