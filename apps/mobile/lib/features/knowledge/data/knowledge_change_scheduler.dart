import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/agent_trigger.dart';
import '../../../core/ai/contracts/source_identity.dart';
import '../../../core/auth/domain_scope.dart';

/// Debounces Knowledge writes into focused agent runs. Capture remains a fast
/// local write; classification and contradiction checks begin after the write
/// has settled instead of waiting for the periodic scheduler.
final class KnowledgeChangeScheduler {
  KnowledgeChangeScheduler(Ref ref)
    : _coordinator = AgentTriggerCoordinator(
        dispatch: (agentId, trigger, _) async {
          final controller = await ref.read(agentRunControllerProvider.future);
          return controller.runOnceById(agentId, trigger: trigger);
        },
      );

  final AgentTriggerCoordinator _coordinator;

  void schedule(String tableName, String rowId) {
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
    final observedAt = DateTime.now().toUtc();
    final family = 'know:$tableName';
    final signal = AgentTriggerSignal(
      kind: AgentTriggerKind.event,
      key: family,
      observedAt: observedAt,
      fingerprint: '$family:$rowId:${observedAt.microsecondsSinceEpoch}',
      source: SourceIdentity(
        domain: DomainScope.knowledge,
        rowFamily: family,
        rowId: rowId,
        fingerprint: '$rowId:${observedAt.microsecondsSinceEpoch}',
      ),
    );
    for (final agentId in agentIds) {
      unawaited(
        _coordinator.submit(
          agentId: agentId,
          spec: AgentTriggerSpec.event(
            id: 'knowledge_row_changed',
            sourceFamily: family,
            debounce: const Duration(milliseconds: 800),
          ),
          signal: signal,
        ),
      );
    }
  }

  void dispose() => _coordinator.dispose();
}
