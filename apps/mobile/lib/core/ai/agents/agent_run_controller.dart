/// Registry-backed agent execution entry points.
///
/// UI/manual actions call [runOnceById]. Platform or foreground catch-up
/// schedulers call [tick]. [AgentSchedule] remains configuration only; this
/// controller is the app-facing execution seam.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent.dart';
import 'agent_registry.dart';
import 'agent_runner.dart';

final agentRunControllerProvider = FutureProvider<AgentRunController>((
  ref,
) async {
  final runner = await ref.watch(agentRunnerProvider.future);
  return AgentRunController(
    runner: runner,
    agents: ref.watch(agentRegistryProvider),
    ref: ref,
  );
});

class AgentRunController {
  const AgentRunController({
    required AgentRunner runner,
    required List<Agent> agents,
    required Ref ref,
  }) : _runner = runner,
       _agents = agents,
       _ref = ref;

  final AgentRunner _runner;
  final List<Agent> _agents;
  final Ref _ref;

  Future<AgentRunResult> runOnceById(String agentId, {DateTime? now}) {
    return _runner.runOnce(
      _agentById(agentId),
      AgentContext(ref: _ref, now: (now ?? DateTime.now()).toUtc()),
    );
  }

  Future<List<AgentRunResult>> tick({
    DateTime? now,
    Iterable<String>? onlyAgentIds,
  }) {
    final idFilter = onlyAgentIds?.toSet();
    final selected = onlyAgentIds == null
        ? _agents
        : [
            for (final agent in _agents)
              if (idFilter!.contains(agent.id)) agent,
          ];
    return _runner.tick(
      agents: selected,
      context: AgentContext(ref: _ref, now: (now ?? DateTime.now()).toUtc()),
    );
  }

  Agent _agentById(String agentId) {
    for (final agent in _agents) {
      if (agent.id == agentId) return agent;
    }
    throw StateError('agent $agentId is not registered');
  }
}
