import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/agents/agent_trigger.dart';
import 'package:naviwealth/core/ai/contracts/source_identity.dart';

final _now = DateTime.utc(2026, 8, 23, 8);

AgentTriggerSignal _signal({
  required AgentTriggerKind kind,
  String fingerprint = 'v1',
  double? previousValue,
  double? currentValue,
  String? previousState,
  String? currentState,
  bool? previouslyFresh,
  bool? currentlyFresh,
  DateTime? lastRunAt,
}) => AgentTriggerSignal(
  kind: kind,
  key: 'fixture',
  observedAt: _now,
  fingerprint: fingerprint,
  source: const SourceIdentity.infrastructure(
    rowFamily: 'know:knowledge_notes',
    rowId: 'note-1',
    fingerprint: 'note-v1',
  ),
  previousValue: previousValue,
  currentValue: currentValue,
  previousState: previousState,
  currentState: currentState,
  previouslyFresh: previouslyFresh,
  currentlyFresh: currentlyFresh,
  lastRunAt: lastRunAt,
);

void main() {
  test(
    'evaluates threshold, transition, freshness, and schedule crossings',
    () {
      expect(
        shouldDispatchAgentTrigger(
          const AgentTriggerSpec.threshold(
            id: 'budget',
            threshold: 0.9,
            direction: AgentThresholdDirection.risesAbove,
          ),
          _signal(
            kind: AgentTriggerKind.threshold,
            previousValue: 0.8,
            currentValue: 0.91,
          ),
        ),
        isTrue,
      );
      expect(
        shouldDispatchAgentTrigger(
          const AgentTriggerSpec.stateTransition(
            id: 'recovery',
            from: 'normal',
            to: 'strained',
          ),
          _signal(
            kind: AgentTriggerKind.stateTransition,
            previousState: 'normal',
            currentState: 'strained',
          ),
        ),
        isTrue,
      );
      expect(
        shouldDispatchAgentTrigger(
          const AgentTriggerSpec.freshness(id: 'health-fresh'),
          _signal(
            kind: AgentTriggerKind.freshness,
            previouslyFresh: false,
            currentlyFresh: true,
          ),
        ),
        isTrue,
      );
      expect(
        shouldDispatchAgentTrigger(
          const AgentTriggerSpec.schedule(
            id: 'fallback',
            schedule: AgentSchedule(interval: Duration(hours: 6)),
          ),
          _signal(
            kind: AgentTriggerKind.schedule,
            lastRunAt: _now.subtract(const Duration(hours: 7)),
          ),
        ),
        isTrue,
      );
    },
  );

  test('debounces writes and suppresses the dispatched fingerprint', () async {
    var calls = 0;
    final coordinator = AgentTriggerCoordinator(
      dispatch: (agentId, trigger, signal) async {
        calls += 1;
        return AgentRunResult(
          agentId: agentId,
          status: AgentRunStatus.completed,
          startedAt: signal.observedAt,
          finishedAt: signal.observedAt,
          payload: <String, Object?>{'trigger': trigger.wire},
        );
      },
    );
    addTearDown(coordinator.dispose);
    const spec = AgentTriggerSpec.event(
      id: 'knowledge-write',
      sourceFamily: 'know:knowledge_notes',
      debounce: Duration(milliseconds: 20),
    );

    final results = await Future.wait(<Future<AgentRunResult?>>[
      coordinator.submit(
        agentId: 'knowledge_agent',
        spec: spec,
        signal: _signal(kind: AgentTriggerKind.event, fingerprint: 'v1'),
      ),
      coordinator.submit(
        agentId: 'knowledge_agent',
        spec: spec,
        signal: _signal(kind: AgentTriggerKind.event, fingerprint: 'v2'),
      ),
      coordinator.submit(
        agentId: 'knowledge_agent',
        spec: spec,
        signal: _signal(kind: AgentTriggerKind.event, fingerprint: 'v3'),
      ),
    ]);
    final duplicate = await coordinator.submit(
      agentId: 'knowledge_agent',
      spec: spec,
      signal: _signal(kind: AgentTriggerKind.event, fingerprint: 'v3'),
    );

    expect(calls, 1);
    expect(
      results.every((result) => result?.status == AgentRunStatus.completed),
      isTrue,
    );
    expect(duplicate, isNull);
  });

  test('maps trigger specs to separate persisted run provenance', () {
    expect(
      const AgentTriggerSpec.threshold(
        id: 'threshold',
        threshold: 1,
        direction: AgentThresholdDirection.risesAbove,
      ).runProvenance,
      AgentRunTrigger.threshold,
    );
    expect(
      const AgentTriggerSpec.stateTransition(
        id: 'transition',
        from: 'a',
        to: 'b',
      ).runProvenance,
      AgentRunTrigger.stateTransition,
    );
  });
}
