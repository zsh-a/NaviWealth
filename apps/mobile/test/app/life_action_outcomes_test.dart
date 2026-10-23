import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        sourceEvaluations: const {
          (rowFamily: 'health:health_metrics', rowId: 'recovery:2026-07-17'):
              LifeSourceEvaluationStatus.complete,
          (rowFamily: 'health:health_metrics', rowId: 'inbox'):
              LifeSourceEvaluationStatus.complete,
        },
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

  test('unsupported sources remain explicit without inferred clearance', () {
    final action = _action(id: 'loading', rowId: 'recovery:2026-07-17');

    final outcomes = deriveLifeActionOutcomes(
      closedActions: [action],
      currentSnapshot: LifeSignalSnapshot(
        observedAt: DateTime.utc(2026, 7, 18),
        events: const <LifeEvent>[],
        evaluatedSourceFamilies: const <String>{},
      ),
    );

    expect(outcomes['loading']?.status, ActionOutcomeStatus.unsupported);
    expect(outcomes['loading']?.evaluatedAt, isNull);
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

    expect(sameMoment['same-time']?.status, ActionOutcomeStatus.pending);
    expect(missingId['missing-id']?.status, ActionOutcomeStatus.unsupported);
  });

  for (final entry in {
    LifeSourceEvaluationStatus.pending: ActionOutcomeStatus.pending,
    LifeSourceEvaluationStatus.incomplete: ActionOutcomeStatus.incomplete,
    LifeSourceEvaluationStatus.failed: ActionOutcomeStatus.failed,
  }.entries) {
    test('preserves ${entry.key.name} without an observation timestamp', () {
      final outcomes = deriveLifeActionOutcomes(
        closedActions: [_action(id: 'action', rowId: 'source')],
        currentSnapshot: LifeSignalSnapshot(
          observedAt: DateTime.utc(2026, 7, 18),
          events: const [],
          evaluatedSourceFamilies: const {},
          sourceEvaluations: {
            (rowFamily: 'health:health_metrics', rowId: 'source'): entry.key,
          },
        ),
      );
      expect(outcomes['action']?.status, entry.value);
      expect(outcomes['action']?.evaluatedAt, isNull);
      expect(outcomes['action']?.isObserved, isFalse);
    });
  }

  test('today being evaluated cannot clear an older source identity', () {
    final outcomes = deriveLifeActionOutcomes(
      closedActions: [_action(id: 'older', rowId: 'recovery:2026-07-17')],
      currentSnapshot: LifeSignalSnapshot(
        observedAt: DateTime.utc(2026, 7, 18),
        events: const [],
        evaluatedSourceFamilies: const {'health:health_metrics'},
        sourceEvaluations: const {
          (rowFamily: 'health:health_metrics', rowId: 'recovery:2026-07-18'):
              LifeSourceEvaluationStatus.complete,
        },
      ),
    );
    expect(outcomes['older']?.status, ActionOutcomeStatus.incomplete);
    expect(outcomes['older']?.evaluatedAt, isNull);
  });

  test(
    'financial outcome reflects live read failures and preserves evidence time',
    () {
      final action = _action(id: 'financial', rowId: 'signal');
      final observedAt = DateTime.utc(2026, 7, 18);
      final stored = AsyncValue.data({
        action.id: ActionOutcomeSummary(
          status: ActionOutcomeStatus.signalCleared,
          sourceLabel: 'signal kind',
          sourceCapturedAt: action.createdAt,
          evaluatedAt: observedAt,
        ),
      });
      ActionOutcomeSummary derive(AsyncValue<Object?> scan) =>
          deriveFinancialActionOutcome(
            action: action,
            stored: stored,
            revalidation: const AsyncValue.data(null),
            scan: scan,
          );
      expect(
        derive(const AsyncValue.loading()).status,
        ActionOutcomeStatus.pending,
      );
      final failed = derive(
        AsyncValue.error(StateError('read failed'), StackTrace.current),
      );
      expect(failed.status, ActionOutcomeStatus.failed);
      expect(failed.evaluatedAt, isNull);
      final recovered = derive(const AsyncValue.data(null));
      expect(recovered.status, ActionOutcomeStatus.signalCleared);
      expect(recovered.evaluatedAt, observedAt);
      expect(
        recovered.sourceLabel,
        'HealthOS',
      ); // Stable action label, not raw signal kind.
    },
  );

  test('an older financial observation cannot evaluate a newer completion', () {
    final action = _action(id: 'financial', rowId: 'signal');
    final outcome = deriveFinancialActionOutcome(
      action: action,
      stored: AsyncValue.data({
        action.id: ActionOutcomeSummary(
          status: ActionOutcomeStatus.signalCleared,
          sourceLabel: 'Source',
          sourceCapturedAt: action.createdAt,
          evaluatedAt: action.completedAt!.subtract(const Duration(days: 1)),
        ),
      }),
      revalidation: const AsyncValue.data(null),
      scan: const AsyncValue.data(null),
    );
    expect(outcome.status, ActionOutcomeStatus.incomplete);
    expect(outcome.evaluatedAt, isNull);
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
