import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/life_action_outcomes.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/action_outcome.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';

void main() {
  test('reports whether the completed action source signal remains active', () {
    final active = _action(id: 'active', rowId: 'recovery:2026-07-17');
    final cleared = _action(id: 'cleared', rowId: 'inbox');
    final dropped = _action(
      id: 'dropped',
      rowId: 'ignored',
      status: ExecutionActionStatus.dropped,
    );

    final outcomes = deriveLifeActionOutcomes(
      closedActions: [active, cleared, dropped],
      currentSnapshot: LifeSignalSnapshot(
        observedAt: DateTime.utc(2026, 7, 18),
        evaluatedSourceFamilies: const <String>{'health:health_metrics'},
        events: [
          LifeEvent(
            id: 'recovery',
            at: DateTime.utc(2026, 7, 18),
            domain: DomainScope.health,
            template: LifeEventTemplate.recoveryAlert,
            actionSuggestion: const LifeActionSuggestion(
              template: LifeActionTemplate.protectRecovery,
              sourceRowFamily: 'health:health_metrics',
              sourceRowId: 'recovery:2026-07-17',
            ),
          ),
        ],
      ),
    );

    expect(outcomes['active']?.status, ActionOutcomeStatus.signalStillActive);
    expect(outcomes['cleared']?.status, ActionOutcomeStatus.signalCleared);
    expect(
      outcomes['cleared']?.attribution,
      ActionOutcomeAttribution.observational,
    );
    expect(outcomes['cleared']?.sourceCapturedAt, DateTime.utc(2026, 7, 17));
    expect(outcomes['cleared']?.evaluatedAt, DateTime.utc(2026, 7, 18));
    expect(outcomes, isNot(contains('dropped')));
  });

  test('does not infer clearance from an unevaluated source family', () {
    final action = _action(id: 'loading', rowId: 'recovery:2026-07-17');

    final outcomes = deriveLifeActionOutcomes(
      closedActions: [action],
      currentSnapshot: LifeSignalSnapshot(
        observedAt: DateTime.utc(2026, 7, 18),
        events: const <LifeEvent>[],
        evaluatedSourceFamilies: const <String>{},
      ),
    );

    expect(outcomes, isEmpty);
  });

  test('requires a later observation and a concrete source id', () {
    final completedAt = DateTime.utc(2026, 7, 17);
    final sameMoment = deriveLifeActionOutcomes(
      closedActions: [_action(id: 'same-time', rowId: 'source')],
      currentSnapshot: LifeSignalSnapshot(
        observedAt: completedAt,
        events: const <LifeEvent>[],
        evaluatedSourceFamilies: const <String>{'health:health_metrics'},
      ),
    );
    final missingId = deriveLifeActionOutcomes(
      closedActions: [_action(id: 'missing-id', rowId: null)],
      currentSnapshot: LifeSignalSnapshot(
        observedAt: completedAt.add(const Duration(days: 1)),
        events: const <LifeEvent>[],
        evaluatedSourceFamilies: const <String>{'health:health_metrics'},
      ),
    );

    expect(sameMoment, isEmpty);
    expect(missingId, isEmpty);
  });
}

ExecutionAction _action({
  required String id,
  required String? rowId,
  ExecutionActionStatus status = ExecutionActionStatus.done,
}) {
  final at = DateTime.utc(2026, 7, 17);
  return ExecutionAction(
    id: id,
    title: id,
    status: status,
    source: ExecutionSourceRef(
      domain: 'health',
      rowFamily: 'health:health_metrics',
      rowId: rowId,
      labelSnapshot: 'HealthOS',
    ),
    createdAt: at,
    completedAt: at,
    sync: SyncMeta(
      ownerUserId: 'user',
      updatedAt: at,
      updatedByDevice: 'device',
      hlc: Hlc.zero('device'),
    ),
  );
}
