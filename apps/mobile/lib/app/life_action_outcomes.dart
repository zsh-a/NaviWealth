import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/lifeos/action_outcome.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/life/data/life_events_provider.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';

Map<String, ActionOutcomeSummary> deriveLifeActionOutcomes({
  required Iterable<ExecutionAction> closedActions,
  required Iterable<LifeEvent> currentSignals,
}) {
  final currentKeys = <String>{
    for (final signal in currentSignals)
      if (signal.actionSuggestion case final suggestion?)
        _sourceKey(suggestion.sourceRowFamily, suggestion.sourceRowId),
  };
  final outcomes = <String, ActionOutcomeSummary>{};
  for (final action in closedActions) {
    if (action.status != ExecutionActionStatus.done) continue;
    final family = action.source.rowFamily;
    if (family == null || family.isEmpty) continue;
    final key = _sourceKey(family, action.source.rowId);
    outcomes[action.id] = ActionOutcomeSummary(
      status: currentKeys.contains(key)
          ? ActionOutcomeStatus.signalStillActive
          : ActionOutcomeStatus.signalCleared,
      sourceLabel:
          action.source.labelSnapshot ?? action.source.domain ?? family,
    );
  }
  return Map.unmodifiable(outcomes);
}

Map<String, ActionOutcomeSummary> watchLifeActionOutcomes(Ref ref) {
  final closed = ref.watch(executionClosedActionsProvider).value;
  if (closed == null) return const {};
  return deriveLifeActionOutcomes(
    closedActions: closed,
    currentSignals: ref.watch(lifeEventCandidatesProvider),
  );
}

String _sourceKey(String family, String? rowId) =>
    '$family\u0000${rowId ?? ''}';
