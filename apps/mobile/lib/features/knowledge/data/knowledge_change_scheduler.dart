import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/agent_run_store.dart';

/// Debounces Knowledge writes into focused agent runs. Capture remains a fast
/// local write; classification and contradiction checks begin after the write
/// has settled instead of waiting for the periodic scheduler.
final class KnowledgeChangeScheduler {
  KnowledgeChangeScheduler(this._ref);

  final Ref _ref;
  final Map<String, Timer> _timers = <String, Timer>{};

  void schedule(String tableName) {
    final agentIds = switch (tableName) {
      'knowledge_notes' => const <String>[
        'knowledge_inbox_triage',
        'knowledge_contradiction',
      ],
      'knowledge_decisions' ||
      'knowledge_principles' ||
      'knowledge_assumptions' => const <String>['knowledge_contradiction'],
      _ => const <String>[],
    };
    for (final agentId in agentIds) {
      _timers.remove(agentId)?.cancel();
      _timers[agentId] = Timer(const Duration(milliseconds: 800), () {
        _timers.remove(agentId);
        unawaited(_run(agentId));
      });
    }
  }

  Future<void> _run(String agentId) async {
    try {
      final controller = await _ref.read(agentRunControllerProvider.future);
      await controller.runOnceById(agentId, trigger: AgentRunTrigger.event);
    } on Object {
      // Best effort: the normal interval schedule remains the fallback when
      // the domain is disabled, the runtime is unavailable, or startup races.
    }
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
