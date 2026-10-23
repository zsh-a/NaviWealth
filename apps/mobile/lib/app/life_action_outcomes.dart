import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/action_outcome.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/inbox/data/financial_inbox_providers.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/features/life/data/life_events_provider.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';

Map<String, ActionOutcomeSummary> deriveLifeActionOutcomes({
  required Iterable<ExecutionAction> closedActions,
  required LifeSignalSnapshot currentSnapshot,
}) {
  final currentKeys = {
    for (final signal in currentSnapshot.events)
      if (signal.actionSuggestion case final suggestion?)
        (rowFamily: suggestion.sourceRowFamily, rowId: suggestion.sourceRowId),
  };
  final outcomes = <String, ActionOutcomeSummary>{};
  for (final action in closedActions) {
    if (action.status != ExecutionActionStatus.done || action.source.isEmpty) {
      continue;
    }
    final family = action.source.rowFamily;
    final rowId = action.source.rowId;
    final completedAt = action.completedAt?.toUtc();
    final source = (rowFamily: family ?? '', rowId: rowId ?? '');
    final evaluation = currentSnapshot.sourceEvaluations[source];
    final ActionOutcomeStatus status;
    if (family == null || rowId == null || family.isEmpty || rowId.isEmpty) {
      status = ActionOutcomeStatus.unsupported;
    } else if (completedAt == null ||
        action.createdAt.toUtc().isAfter(completedAt)) {
      status = ActionOutcomeStatus.incomplete;
    } else if (!currentSnapshot.observedAt.toUtc().isAfter(completedAt)) {
      status = ActionOutcomeStatus.pending;
    } else {
      status = switch (evaluation) {
        LifeSourceEvaluationStatus.complete =>
          currentKeys.contains(source)
              ? ActionOutcomeStatus.signalStillActive
              : ActionOutcomeStatus.signalCleared,
        LifeSourceEvaluationStatus.pending => ActionOutcomeStatus.pending,
        LifeSourceEvaluationStatus.failed => ActionOutcomeStatus.failed,
        LifeSourceEvaluationStatus.incomplete => ActionOutcomeStatus.incomplete,
        null =>
          currentSnapshot.sourceEvaluations.keys.any(
                (key) => key.rowFamily == family,
              )
              ? ActionOutcomeStatus.incomplete
              : ActionOutcomeStatus.unsupported,
      };
    }
    outcomes[action.id] = _summary(
      action,
      status,
      evaluatedAt:
          status == ActionOutcomeStatus.signalCleared ||
              status == ActionOutcomeStatus.signalStillActive
          ? currentSnapshot.observedAt.toUtc()
          : null,
    );
  }
  return Map.unmodifiable(outcomes);
}

AsyncValue<Map<String, ActionOutcomeSummary>> watchLifeActionOutcomes(Ref ref) {
  final closedAsync = ref.watch(executionClosedActionsProvider);
  if (closedAsync.hasError) {
    return AsyncValue.error(closedAsync.error!, closedAsync.stackTrace!);
  }
  if (closedAsync.isLoading) return const AsyncValue.loading();
  final closed = closedAsync.requireValue;
  final outcomes = {
    ...deriveLifeActionOutcomes(
      closedActions: closed,
      currentSnapshot: ref.watch(lifeSignalSnapshotProvider),
    ),
  };
  final financial = closed.where(
    (action) =>
        action.status == ExecutionActionStatus.done &&
        action.source.rowFamily == 'fin:financial_signals',
  );
  if (financial.isNotEmpty) {
    final stored = ref.watch(financialActionOutcomeSummariesProvider);
    final revalidation = ref.watch(financialSignalRevalidationProvider);
    final scan = ref.watch(financialSignalScanCandidatesProvider);
    for (final action in financial) {
      outcomes[action.id] = deriveFinancialActionOutcome(
        action: action,
        stored: stored,
        revalidation: revalidation,
        scan: scan,
      );
    }
  }
  return AsyncValue.data(Map.unmodifiable(outcomes));
}

ActionOutcomeSummary deriveFinancialActionOutcome({
  required ExecutionAction action,
  required AsyncValue<Map<String, ActionOutcomeSummary>> stored,
  required AsyncValue<Object?> revalidation,
  required AsyncValue<Object?> scan,
}) {
  final observed = stored.value?[action.id];
  final completedAt = action.completedAt;
  final status = stored.hasError || revalidation.hasError || scan.hasError
      ? ActionOutcomeStatus.failed
      : stored.isLoading || revalidation.isLoading || scan.isLoading
      ? ActionOutcomeStatus.pending
      : ActionOutcomeStatus.incomplete;
  final current =
      observed != null &&
      observed.isObserved &&
      completedAt != null &&
      !action.createdAt.toUtc().isAfter(completedAt.toUtc()) &&
      observed.evaluatedAt?.isAfter(completedAt) == true;
  return _summary(
    action,
    status == ActionOutcomeStatus.incomplete && current
        ? observed.status
        : status,
    evaluatedAt: status == ActionOutcomeStatus.incomplete && current
        ? observed.evaluatedAt
        : null,
  );
}

ActionOutcomeSummary _summary(
  ExecutionAction action,
  ActionOutcomeStatus status, {
  DateTime? evaluatedAt,
}) => ActionOutcomeSummary(
  status: status,
  sourceLabel:
      action.source.labelSnapshot ??
      action.source.domain ??
      action.source.rowFamily ??
      '',
  sourceCapturedAt: action.createdAt.toUtc(),
  evaluatedAt: evaluatedAt,
);

VoidCallback? watchActionOutcomeRefresh(Ref ref, String actionId) {
  final actions = ref.watch(executionClosedActionsProvider);
  if (actions.hasError) {
    return () => ref.invalidate(executionClosedActionsProvider);
  }
  final action = actions.value
      ?.where((action) => action.id == actionId)
      .firstOrNull;
  if (action == null) return null;
  final family = action.source.rowFamily;
  final rowId = action.source.rowId;
  final scope = switch (family) {
    'fin:financial_signals' ||
    'fin:budgets' ||
    'fin:journal_entries' => DomainScope.finance,
    'health:health_metrics' => DomainScope.health,
    _ => null,
  };
  if (scope == null ||
      !ref
          .watch(activeDomainPacksProvider)
          .any((pack) => pack.scope == scope)) {
    return null;
  }
  return switch (family) {
    'fin:financial_signals' => () => refreshFinancialSignalEvaluation(ref),
    'fin:budgets' when rowId?.startsWith('month:') == true => () {
      final month = rowId!.substring('month:'.length);
      ref.invalidate(budgetsForMonthProvider(month));
      ref.invalidate(journalExpensesStreamProvider);
      ref.invalidate(fxRatesStreamProvider);
    },
    'fin:journal_entries' => () {
      ref.invalidate(allAccountsStreamProvider);
      ref.invalidate(activityFeedProvider);
    },
    'health:health_metrics' => () {
      ref.invalidate(healthTodaySnapshotProvider);
      ref.invalidate(recoverySignalProvider);
    },
    _ => null,
  };
}
