import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';

import '../data/rebalance_execution_store.dart';
import '../domain/rebalance_execution.dart';
import 'rebalance_trade_validation.dart';

abstract interface class RebalanceStopSignal {
  bool get isStopped;
}

final class MutableRebalanceStopSignal implements RebalanceStopSignal {
  bool _stopped = false;

  @override
  bool get isStopped => _stopped;

  void stop() => _stopped = true;
}

final class NeverRebalanceStopSignal implements RebalanceStopSignal {
  const NeverRebalanceStopSignal();

  @override
  bool get isStopped => false;
}

enum RebalanceExecutionFailureCode {
  sessionNotFound,
  sessionArchived,
  stopped,
  blocked,
  recoveryBlocked,
  undoFailed,
  validationFailed,
  businessFailed,
  staleAttempt,
}

final class RebalanceExecutionFailure {
  const RebalanceExecutionFailure({
    required this.code,
    this.itemId,
    this.cause,
  });

  final RebalanceExecutionFailureCode code;
  final String? itemId;
  final Object? cause;
}

final class RebalanceExecutionBatchResult {
  const RebalanceExecutionBatchResult({
    required this.completedItemIds,
    required this.failures,
    required this.stopped,
  });

  final List<String> completedItemIds;
  final List<RebalanceExecutionFailure> failures;
  final bool stopped;

  bool get isSuccess => failures.isEmpty && !stopped;
}

final class RebalanceExecutionCoordinator {
  RebalanceExecutionCoordinator({
    required AppDatabase db,
    required RebalanceExecutionStore store,
    required RebalanceTradeValidation validation,
    required TradeEntrySubmissionService tradeSubmission,
    required Future<String> Function() currentUserId,
  }) : _db = db,
       _store = store,
       _validation = validation,
       _tradeSubmission = tradeSubmission,
       _currentUserId = currentUserId {
    if (!store.isBoundTo(db) ||
        !validation.isBoundTo(db) ||
        !tradeSubmission.isBoundTo(db)) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.databaseMismatch,
        'Rebalance coordinator dependencies must share one AppDatabase.',
      );
    }
  }

  final AppDatabase _db;
  final RebalanceExecutionStore _store;
  final RebalanceTradeValidation _validation;
  final TradeEntrySubmissionService _tradeSubmission;
  final Future<String> Function() _currentUserId;

  bool isBoundTo(AppDatabase database) => identical(_db, database);

  Future<RebalanceExecutionBatchResult> applySession({
    required String sessionId,
    RebalanceStopSignal stop = const NeverRebalanceStopSignal(),
    Duration leaseDuration = const Duration(minutes: 2),
  }) async {
    final owner = await _currentUserId();
    final session = await _store.getSession(ownerUserId: owner, id: sessionId);
    if (session == null) {
      return const RebalanceExecutionBatchResult(
        completedItemIds: [],
        failures: [
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.sessionNotFound,
          ),
        ],
        stopped: true,
      );
    }
    if (session.status == RebalanceExecutionSessionStatus.archived) {
      return const RebalanceExecutionBatchResult(
        completedItemIds: [],
        failures: [
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.sessionArchived,
          ),
        ],
        stopped: true,
      );
    }
    final completed = <String>[];
    final failures = <RebalanceExecutionFailure>[];
    for (final item in session.items) {
      if (stop.isStopped) {
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.stopped,
            itemId: item.id,
          ),
        );
        return _result(completed, failures, stopped: true);
      }
      if (item.state != RebalanceExecutionItemState.ready &&
          item.state != RebalanceExecutionItemState.applyFailed &&
          item.state != RebalanceExecutionItemState.applying) {
        continue;
      }
      RebalanceExecutionAttempt? attempt;
      try {
        attempt = await _store.claimApply(
          ownerUserId: owner,
          itemId: item.id,
          leaseDuration: leaseDuration,
        );
      } on RebalanceExecutionConflict catch (error) {
        failures.add(
          await _claimBoundaryFailure(owner, sessionId, item.id, error),
        );
        return _result(completed, failures, stopped: true);
      } on RebalanceExecutionNotFound catch (error) {
        failures.add(
          await _claimBoundaryFailure(owner, sessionId, item.id, error),
        );
        return _result(completed, failures, stopped: true);
      }
      if (attempt == null) {
        failures.add(
          await _claimBoundaryFailure(owner, sessionId, item.id, null),
        );
        return _result(completed, failures, stopped: true);
      }
      if (stop.isStopped) {
        final outcome = await _releaseApplyIfCurrent(owner, attempt);
        if (outcome == _AttemptMutationOutcome.stale) {
          failures.add(_staleFailure(item.id));
          return _result(completed, failures, stopped: true);
        }
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.stopped,
            itemId: item.id,
          ),
        );
        return _result(completed, failures, stopped: true);
      }

      late final PreparedTradeSubmission prepared;
      try {
        final request = _validation.validateSnapshot(attempt.item);
        prepared = await _tradeSubmission.prepare(request);
      } catch (error) {
        final outcome = await _markApplyFailedIfCurrent(owner, attempt, error);
        if (outcome == _AttemptMutationOutcome.stale) {
          failures.add(_staleFailure(item.id, error));
          return _result(completed, failures, stopped: true);
        }
        failures.add(
          RebalanceExecutionFailure(
            code: error is RebalanceTradeValidationError
                ? RebalanceExecutionFailureCode.validationFailed
                : RebalanceExecutionFailureCode.businessFailed,
            itemId: item.id,
            cause: error,
          ),
        );
        continue;
      }
      if (stop.isStopped) {
        final outcome = await _releaseApplyIfCurrent(owner, attempt);
        if (outcome == _AttemptMutationOutcome.stale) {
          failures.add(_staleFailure(item.id));
          return _result(completed, failures, stopped: true);
        }
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.stopped,
            itemId: item.id,
          ),
        );
        return _result(completed, failures, stopped: true);
      }

      try {
        await _store.renewApply(
          ownerUserId: owner,
          itemId: item.id,
          attemptToken: attempt.token,
          leaseDuration: leaseDuration,
        );
      } on RebalanceStaleAttempt catch (error) {
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.staleAttempt,
            itemId: item.id,
            cause: error,
          ),
        );
        return _result(completed, failures, stopped: true);
      }
      if (stop.isStopped) {
        final outcome = await _releaseApplyIfCurrent(owner, attempt);
        if (outcome == _AttemptMutationOutcome.stale) {
          failures.add(_staleFailure(item.id));
          return _result(completed, failures, stopped: true);
        }
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.stopped,
            itemId: item.id,
          ),
        );
        return _result(completed, failures, stopped: true);
      }

      try {
        await _store.runApplyTransaction(
          ownerUserId: owner,
          itemId: item.id,
          attemptToken: attempt.token,
          mutate: (scope, claimed) async {
            if (claimed.request != attempt!.item.request) {
              throw const RebalanceStaleAttempt(
                'Reviewed request changed after preparation.',
              );
            }
            await _validation.validateFresh(scope, claimed);
            return _tradeSubmission.commitInTransaction(scope, prepared);
          },
        );
        completed.add(item.id);
      } on RebalanceStaleAttempt catch (error) {
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.staleAttempt,
            itemId: item.id,
            cause: error,
          ),
        );
        return _result(completed, failures, stopped: true);
      } catch (error) {
        final outcome = await _markApplyFailedIfCurrent(owner, attempt, error);
        if (outcome == _AttemptMutationOutcome.stale) {
          failures.add(_staleFailure(item.id, error));
          return _result(completed, failures, stopped: true);
        }
        failures.add(
          RebalanceExecutionFailure(
            code: error is RebalanceTradeValidationError
                ? RebalanceExecutionFailureCode.validationFailed
                : RebalanceExecutionFailureCode.businessFailed,
            itemId: item.id,
            cause: error,
          ),
        );
      }
    }
    return _result(completed, failures, stopped: stop.isStopped);
  }

  Future<RebalanceExecutionBatchResult> undoSession({
    required String sessionId,
    RebalanceStopSignal stop = const NeverRebalanceStopSignal(),
    Duration leaseDuration = const Duration(minutes: 2),
  }) async {
    final owner = await _currentUserId();
    final session = await _store.getSession(ownerUserId: owner, id: sessionId);
    if (session == null) {
      return const RebalanceExecutionBatchResult(
        completedItemIds: [],
        failures: [
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.sessionNotFound,
          ),
        ],
        stopped: true,
      );
    }
    if (session.status == RebalanceExecutionSessionStatus.archived) {
      return const RebalanceExecutionBatchResult(
        completedItemIds: [],
        failures: [
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.sessionArchived,
          ),
        ],
        stopped: true,
      );
    }
    final items = await _store.listAppliedForUndo(
      ownerUserId: owner,
      sessionId: sessionId,
    );
    final completed = <String>[];
    final failures = <RebalanceExecutionFailure>[];
    for (final item in items) {
      if (stop.isStopped) {
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.stopped,
            itemId: item.id,
          ),
        );
        return _result(completed, failures, stopped: true);
      }
      if (item.state == RebalanceExecutionItemState.recoveryBlocked) {
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.recoveryBlocked,
            itemId: item.id,
          ),
        );
        return _result(completed, failures, stopped: true);
      }
      RebalanceExecutionAttempt? attempt;
      try {
        attempt = await _store.claimUndo(
          ownerUserId: owner,
          itemId: item.id,
          leaseDuration: leaseDuration,
        );
      } on RebalanceExecutionConflict catch (error) {
        failures.add(
          await _claimBoundaryFailure(owner, sessionId, item.id, error),
        );
        return _result(completed, failures, stopped: true);
      } on RebalanceExecutionNotFound catch (error) {
        failures.add(
          await _claimBoundaryFailure(owner, sessionId, item.id, error),
        );
        return _result(completed, failures, stopped: true);
      }
      if (attempt == null) {
        failures.add(
          await _claimBoundaryFailure(owner, sessionId, item.id, null),
        );
        return _result(completed, failures, stopped: true);
      }
      if (stop.isStopped) {
        final outcome = await _releaseUndoIfCurrent(owner, attempt);
        if (outcome == _AttemptMutationOutcome.stale) {
          failures.add(_staleFailure(item.id));
          return _result(completed, failures, stopped: true);
        }
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.stopped,
            itemId: item.id,
          ),
        );
        return _result(completed, failures, stopped: true);
      }

      try {
        await _store.runUndoTransaction(
          ownerUserId: owner,
          itemId: item.id,
          attemptToken: attempt.token,
          mutate: (scope, claimed) async {
            final receipt = claimed.receipt;
            if (receipt == null) {
              throw const RebalanceTradeValidationError(
                RebalanceTradeValidationCode.identityMismatch,
                'Undo claim has no trade receipt.',
              );
            }
            await _tradeSubmission.undoInTransaction(scope, receipt);
          },
        );
        completed.add(item.id);
      } on RebalanceStaleAttempt catch (error) {
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.staleAttempt,
            itemId: item.id,
            cause: error,
          ),
        );
        return _result(completed, failures, stopped: true);
      } catch (error) {
        final outcome = await _markUndoFailedIfCurrent(owner, attempt, error);
        if (outcome == _AttemptMutationOutcome.stale) {
          failures.add(_staleFailure(item.id, error));
          return _result(completed, failures, stopped: true);
        }
        failures.add(
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.businessFailed,
            itemId: item.id,
            cause: error,
          ),
        );
        return _result(completed, failures, stopped: true);
      }
    }
    return _result(completed, failures, stopped: stop.isStopped);
  }

  RebalanceExecutionBatchResult _result(
    List<String> completed,
    List<RebalanceExecutionFailure> failures, {
    required bool stopped,
  }) => RebalanceExecutionBatchResult(
    completedItemIds: List.unmodifiable(completed),
    failures: List.unmodifiable(failures),
    stopped: stopped,
  );

  Future<_AttemptMutationOutcome> _releaseApplyIfCurrent(
    String owner,
    RebalanceExecutionAttempt attempt,
  ) async {
    try {
      await _store.releaseApply(
        ownerUserId: owner,
        itemId: attempt.item.id,
        attemptToken: attempt.token,
      );
      return _AttemptMutationOutcome.updated;
    } on RebalanceStaleAttempt {
      return _AttemptMutationOutcome.stale;
    }
  }

  Future<_AttemptMutationOutcome> _markApplyFailedIfCurrent(
    String owner,
    RebalanceExecutionAttempt attempt,
    Object error,
  ) async {
    try {
      await _store.markApplyFailed(
        ownerUserId: owner,
        itemId: attempt.item.id,
        attemptToken: attempt.token,
        error: error.toString(),
      );
      return _AttemptMutationOutcome.updated;
    } on RebalanceStaleAttempt {
      return _AttemptMutationOutcome.stale;
    }
  }

  Future<_AttemptMutationOutcome> _releaseUndoIfCurrent(
    String owner,
    RebalanceExecutionAttempt attempt,
  ) async {
    try {
      await _store.releaseUndo(
        ownerUserId: owner,
        itemId: attempt.item.id,
        attemptToken: attempt.token,
      );
      return _AttemptMutationOutcome.updated;
    } on RebalanceStaleAttempt {
      return _AttemptMutationOutcome.stale;
    }
  }

  Future<_AttemptMutationOutcome> _markUndoFailedIfCurrent(
    String owner,
    RebalanceExecutionAttempt attempt,
    Object error,
  ) async {
    try {
      await _store.markUndoFailed(
        ownerUserId: owner,
        itemId: attempt.item.id,
        attemptToken: attempt.token,
        error: error.toString(),
      );
      return _AttemptMutationOutcome.updated;
    } on RebalanceStaleAttempt {
      return _AttemptMutationOutcome.stale;
    }
  }

  Future<RebalanceExecutionFailure> _claimBoundaryFailure(
    String owner,
    String sessionId,
    String itemId,
    Object? cause,
  ) async {
    final session = await _store.getSession(ownerUserId: owner, id: sessionId);
    if (session == null) {
      return RebalanceExecutionFailure(
        code: RebalanceExecutionFailureCode.sessionNotFound,
        itemId: itemId,
        cause: cause,
      );
    }
    if (session.status == RebalanceExecutionSessionStatus.archived) {
      return RebalanceExecutionFailure(
        code: RebalanceExecutionFailureCode.sessionArchived,
        itemId: itemId,
        cause: cause,
      );
    }
    return RebalanceExecutionFailure(
      code: cause is RebalanceExecutionNotFound
          ? RebalanceExecutionFailureCode.staleAttempt
          : RebalanceExecutionFailureCode.blocked,
      itemId: itemId,
      cause: cause,
    );
  }

  RebalanceExecutionFailure _staleFailure(String itemId, [Object? cause]) =>
      RebalanceExecutionFailure(
        code: RebalanceExecutionFailureCode.staleAttempt,
        itemId: itemId,
        cause: cause,
      );
}

enum _AttemptMutationOutcome { updated, stale }
