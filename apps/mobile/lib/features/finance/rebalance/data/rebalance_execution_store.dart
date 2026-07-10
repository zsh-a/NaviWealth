import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:uuid/uuid.dart';

import '../domain/rebalance_execution.dart';
import '../domain/rebalance_models.dart';
import 'rebalance_execution_codecs.dart';

typedef RebalanceExecutionClock = DateTime Function();
typedef RebalanceApplyMutation =
    Future<TradeMutationReceipt> Function(
      AppDatabaseTransactionScope scope,
      RebalanceExecutionItem claimed,
    );
typedef RebalanceUndoMutation =
    Future<void> Function(
      AppDatabaseTransactionScope scope,
      RebalanceExecutionItem claimed,
    );

/// Owner-scoped local coordinator for resumable rebalance execution.
final class RebalanceExecutionStore {
  RebalanceExecutionStore(
    this._db, {
    Uuid uuid = const Uuid(),
    RebalanceExecutionClock? clock,
  }) : _uuid = uuid,
       _clock = clock ?? _utcNow;

  final AppDatabase _db;
  final Uuid _uuid;
  final RebalanceExecutionClock _clock;

  bool isBoundTo(AppDatabase database) => identical(_db, database);

  Future<RebalanceExecutionSession> createOrResume({
    required String ownerUserId,
    required RebalancePlan plan,
    bool archiveExisting = false,
  }) async {
    _requireOwner(ownerUserId);
    final planJson = RebalancePlanCodec.encode(plan);
    final canonicalPlan = RebalancePlanCodec.decode(planJson);
    final fingerprint = RebalancePlanFingerprint.compute(plan);
    final now = _now();

    return _db.transactionWithScope((scope) async {
      if (archiveExisting) {
        final active = await _activeSessionRow(ownerUserId);
        if (active != null) {
          final existingFingerprint = active.read<String>('plan_fingerprint');
          if (existingFingerprint == fingerprint) {
            return _sessionFromRow(active);
          }
          await _archiveRow(
            ownerUserId: ownerUserId,
            sessionId: active.read<String>('id'),
            now: now,
          );
        }
      }

      final sessionId = _uuid.v4();
      final inserted = await _db.customUpdate(
        'INSERT INTO rebalance_execution_sessions '
        '(id, owner_user_id, status, plan_json, plan_fingerprint, '
        ' created_at_iso, updated_at_iso, archived_at_iso) '
        "VALUES (?1, ?2, 'active', ?3, ?4, ?5, ?5, NULL) "
        "ON CONFLICT(owner_user_id) WHERE status = 'active' DO NOTHING",
        variables: [
          Variable.withString(sessionId),
          Variable.withString(ownerUserId),
          Variable.withString(planJson),
          Variable.withString(fingerprint),
          Variable.withString(_iso(now)),
        ],
      );
      if (inserted == 0) {
        final winner = await _activeSessionRow(ownerUserId);
        if (winner?.read<String>('plan_fingerprint') == fingerprint) {
          return _sessionFromRow(winner!);
        }
        throw const RebalanceExecutionConflict(
          'A different rebalance plan won the active-session race.',
        );
      }
      for (
        var position = 0;
        position < canonicalPlan.trades.length;
        position++
      ) {
        final itemId = _uuid.v4();
        await _db.customInsert(
          'INSERT INTO rebalance_execution_items '
          '(id, session_id, owner_user_id, position, suggestion_json, '
          ' request_json, receipt_json, state, error, attempt_token, '
          ' lease_until_iso, applied_sequence, recovery_was_applied, '
          ' created_at_iso, updated_at_iso) '
          "VALUES (?1, ?2, ?3, ?4, ?5, NULL, NULL, 'needsDetails', "
          'NULL, NULL, NULL, NULL, 0, ?6, ?6)',
          variables: [
            Variable.withString(itemId),
            Variable.withString(sessionId),
            Variable.withString(ownerUserId),
            Variable.withInt(position),
            Variable.withString(
              RebalanceSuggestionCodec.encode(canonicalPlan.trades[position]),
            ),
            Variable.withString(_iso(now)),
          ],
        );
      }
      return (await getSession(ownerUserId: ownerUserId, id: sessionId))!;
    });
  }

  Future<RebalanceExecutionSession?> getActive(String ownerUserId) async {
    _requireOwner(ownerUserId);
    final row = await _activeSessionRow(ownerUserId);
    return row == null ? null : _sessionFromRow(row);
  }

  Future<RebalanceExecutionSession?> getSession({
    required String ownerUserId,
    required String id,
  }) async {
    _requireOwner(ownerUserId);
    final rows = await _db
        .customSelect(
          'SELECT * FROM rebalance_execution_sessions '
          'WHERE id = ?1 AND owner_user_id = ?2',
          variables: [
            Variable.withString(id),
            Variable.withString(ownerUserId),
          ],
        )
        .get();
    return rows.isEmpty ? null : _sessionFromRow(rows.single);
  }

  Future<RebalanceExecutionItem?> getItem({
    required String ownerUserId,
    required String id,
  }) async {
    _requireOwner(ownerUserId);
    final row = await _itemRow(ownerUserId: ownerUserId, id: id);
    return row == null ? null : _itemFromRow(row);
  }

  Future<void> archive({
    required String ownerUserId,
    required String sessionId,
  }) async {
    _requireOwner(ownerUserId);
    final changed = await _archiveRow(
      ownerUserId: ownerUserId,
      sessionId: sessionId,
      now: _now(),
    );
    if (changed != 1) {
      throw const RebalanceExecutionConflict(
        'Only an active owned session can be archived.',
      );
    }
  }

  Future<RebalanceExecutionItem> saveRequest({
    required String ownerUserId,
    required String itemId,
    required RebalanceExecutionRequest request,
  }) async {
    _requireOwner(ownerUserId);
    if (request.transactionId != itemId) {
      throw const RebalanceExecutionInvariantError(
        'Request transactionId must equal the item id.',
      );
    }
    final requestJson = RebalanceExecutionRequestCodec.encode(request);
    if (request.account.sync.ownerUserId != ownerUserId) {
      throw const RebalanceExecutionConflict(
        'Request snapshots do not belong to the caller.',
      );
    }
    final changed = await _db.customUpdate(
      'UPDATE rebalance_execution_items '
      "SET request_json = ?1, state = 'ready', error = NULL, "
      '    attempt_token = NULL, lease_until_iso = NULL, updated_at_iso = ?2 '
      'WHERE id = ?3 AND owner_user_id = ?4 '
      "  AND state IN ('needsDetails', 'ready', 'applyFailed') "
      '  AND EXISTS (SELECT 1 FROM rebalance_execution_sessions s '
      '    WHERE s.id = rebalance_execution_items.session_id '
      '      AND s.owner_user_id = ?4 AND s.status = \'active\')',
      variables: [
        Variable.withString(requestJson),
        Variable.withString(_iso(_now())),
        Variable.withString(itemId),
        Variable.withString(ownerUserId),
      ],
    );
    if (changed != 1) {
      throw const RebalanceExecutionConflict(
        'Request cannot be saved for this item state or archived session.',
      );
    }
    return (await getItem(ownerUserId: ownerUserId, id: itemId))!;
  }

  Future<RebalanceExecutionItem> markSkipped({
    required String ownerUserId,
    required String itemId,
  }) async {
    _requireOwner(ownerUserId);
    final changed = await _db.customUpdate(
      'UPDATE rebalance_execution_items '
      "SET state = 'skipped', error = NULL, attempt_token = NULL, "
      '    lease_until_iso = NULL, updated_at_iso = ?1 '
      'WHERE id = ?2 AND owner_user_id = ?3 '
      "  AND state IN ('needsDetails', 'ready', 'applyFailed') "
      '  AND EXISTS (SELECT 1 FROM rebalance_execution_sessions s '
      '    WHERE s.id = rebalance_execution_items.session_id '
      '      AND s.owner_user_id = ?3 AND s.status = \'active\')',
      variables: [
        Variable.withString(_iso(_now())),
        Variable.withString(itemId),
        Variable.withString(ownerUserId),
      ],
    );
    if (changed != 1) {
      throw const RebalanceExecutionConflict(
        'Item cannot be skipped in its current state.',
      );
    }
    return (await getItem(ownerUserId: ownerUserId, id: itemId))!;
  }

  Future<RebalanceExecutionAttempt?> claimApply({
    required String ownerUserId,
    required String itemId,
    required Duration leaseDuration,
  }) => _claim(
    ownerUserId: ownerUserId,
    itemId: itemId,
    leaseDuration: leaseDuration,
    phase: RebalanceExecutionPhase.apply,
  );

  Future<RebalanceExecutionAttempt?> claimUndo({
    required String ownerUserId,
    required String itemId,
    required Duration leaseDuration,
  }) => _claim(
    ownerUserId: ownerUserId,
    itemId: itemId,
    leaseDuration: leaseDuration,
    phase: RebalanceExecutionPhase.undo,
  );

  Future<DateTime> renewApply({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required Duration leaseDuration,
  }) => _renew(
    ownerUserId: ownerUserId,
    itemId: itemId,
    attemptToken: attemptToken,
    leaseDuration: leaseDuration,
    phase: RebalanceExecutionPhase.apply,
  );

  Future<DateTime> renewUndo({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required Duration leaseDuration,
  }) => _renew(
    ownerUserId: ownerUserId,
    itemId: itemId,
    attemptToken: attemptToken,
    leaseDuration: leaseDuration,
    phase: RebalanceExecutionPhase.undo,
  );

  Future<void> releaseApply({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
  }) => _finishAttempt(
    ownerUserId: ownerUserId,
    itemId: itemId,
    attemptToken: attemptToken,
    phase: RebalanceExecutionPhase.apply,
    nextState: RebalanceExecutionItemState.ready,
    error: null,
  );

  Future<void> markApplyFailed({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required String error,
  }) => _finishAttempt(
    ownerUserId: ownerUserId,
    itemId: itemId,
    attemptToken: attemptToken,
    phase: RebalanceExecutionPhase.apply,
    nextState: RebalanceExecutionItemState.applyFailed,
    error: error,
  );

  Future<void> releaseUndo({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
  }) => _finishAttempt(
    ownerUserId: ownerUserId,
    itemId: itemId,
    attemptToken: attemptToken,
    phase: RebalanceExecutionPhase.undo,
    nextState: RebalanceExecutionItemState.applied,
    error: null,
  );

  Future<void> markUndoFailed({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required String error,
  }) => _finishAttempt(
    ownerUserId: ownerUserId,
    itemId: itemId,
    attemptToken: attemptToken,
    phase: RebalanceExecutionPhase.undo,
    nextState: RebalanceExecutionItemState.undoFailed,
    error: error,
  );

  /// Runs the trade mutation and execution-state finalization atomically.
  ///
  /// Callers must prepare external inputs before entering this callback. All
  /// database writes in [mutate] must use this store's [AppDatabase] so they
  /// participate in the transaction owned here.
  Future<RebalanceExecutionItem> runApplyTransaction({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required RebalanceApplyMutation mutate,
  }) async {
    _requireOwner(ownerUserId);
    return _db.transactionWithScope((scope) async {
      final claimed = await _claimedForTransaction(
        ownerUserId: ownerUserId,
        itemId: itemId,
        attemptToken: attemptToken,
        phase: RebalanceExecutionPhase.apply,
      );
      final receipt = await mutate(scope, claimed);
      return _finalizeApply(
        ownerUserId: ownerUserId,
        itemId: itemId,
        attemptToken: attemptToken,
        claimed: claimed,
        receipt: receipt,
      );
    });
  }

  /// Runs the trade reversal and execution-state finalization atomically.
  ///
  /// Callers must prepare external inputs before entering this callback. All
  /// database writes in [mutate] must use this store's [AppDatabase] so they
  /// participate in the transaction owned here.
  Future<RebalanceExecutionItem> runUndoTransaction({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required RebalanceUndoMutation mutate,
  }) async {
    _requireOwner(ownerUserId);
    return _db.transactionWithScope((scope) async {
      final claimed = await _claimedForTransaction(
        ownerUserId: ownerUserId,
        itemId: itemId,
        attemptToken: attemptToken,
        phase: RebalanceExecutionPhase.undo,
      );
      await mutate(scope, claimed);
      return _finalizeUndo(
        ownerUserId: ownerUserId,
        itemId: itemId,
        attemptToken: attemptToken,
        claimed: claimed,
      );
    });
  }

  Future<RebalanceExecutionItem> _finalizeApply({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required RebalanceExecutionItem claimed,
    required TradeMutationReceipt receipt,
  }) async {
    if (receipt.transactionId != itemId) {
      throw const RebalanceExecutionInvariantError(
        'Receipt transactionId must equal the item id.',
      );
    }
    final receiptJson = TradeMutationReceiptCodec.encode(receipt);
    if (receipt.assetAfter.sync.ownerUserId != ownerUserId) {
      throw const RebalanceExecutionConflict(
        'Receipt rows do not belong to the caller.',
      );
    }
    final request = claimed.request;
    if (request == null ||
        request.transactionId != itemId ||
        request.account.sync.ownerUserId != ownerUserId) {
      throw const RebalanceExecutionConflict(
        'Claimed item request does not match the caller and transaction.',
      );
    }
    final now = _now();
    final changed = await _db.customUpdate(
      'UPDATE rebalance_execution_items '
      "SET state = 'applied', receipt_json = ?1, "
      '    applied_sequence = (SELECT COALESCE(MAX(peer.applied_sequence), 0) + 1 '
      '      FROM rebalance_execution_items peer '
      '      WHERE peer.session_id = rebalance_execution_items.session_id), '
      '    error = NULL, attempt_token = NULL, lease_until_iso = NULL, '
      '    recovery_was_applied = 0, updated_at_iso = ?2 '
      'WHERE id = ?3 AND owner_user_id = ?4 AND state = \'applying\' '
      '  AND attempt_token = ?5 AND lease_until_iso > ?2 '
      '  AND request_json = ?6 '
      '  AND EXISTS (SELECT 1 FROM rebalance_execution_sessions s '
      '    WHERE s.id = rebalance_execution_items.session_id '
      '      AND s.owner_user_id = ?4 AND s.status = \'active\')',
      variables: [
        Variable.withString(receiptJson),
        Variable.withString(_iso(now)),
        Variable.withString(itemId),
        Variable.withString(ownerUserId),
        Variable.withString(attemptToken),
        Variable.withString(claimed.rawRequestJson!),
      ],
    );
    if (changed != 1) _throwStale(itemId);
    return (await getItem(ownerUserId: ownerUserId, id: itemId))!;
  }

  Future<RebalanceExecutionItem> _finalizeUndo({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required RebalanceExecutionItem claimed,
  }) async {
    final now = _now();
    final changed = await _db.customUpdate(
      'UPDATE rebalance_execution_items '
      "SET state = 'undone', error = NULL, attempt_token = NULL, "
      '    lease_until_iso = NULL, updated_at_iso = ?1 '
      'WHERE id = ?2 AND owner_user_id = ?3 AND state = \'undoing\' '
      '  AND attempt_token = ?4 AND lease_until_iso > ?1 '
      '  AND request_json = ?5 AND receipt_json = ?6 '
      '  AND applied_sequence = ?7 '
      '  AND EXISTS (SELECT 1 FROM rebalance_execution_sessions s '
      '    WHERE s.id = rebalance_execution_items.session_id '
      '      AND s.owner_user_id = ?3 AND s.status = \'active\')',
      variables: [
        Variable.withString(_iso(now)),
        Variable.withString(itemId),
        Variable.withString(ownerUserId),
        Variable.withString(attemptToken),
        Variable.withString(claimed.rawRequestJson!),
        Variable.withString(claimed.rawReceiptJson!),
        Variable.withInt(claimed.appliedSequence!),
      ],
    );
    if (changed != 1) _throwStale(itemId);
    return (await getItem(ownerUserId: ownerUserId, id: itemId))!;
  }

  Future<RebalanceExecutionItem> _claimedForTransaction({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required RebalanceExecutionPhase phase,
  }) async {
    final action = await _itemForAction(
      ownerUserId: ownerUserId,
      itemId: itemId,
    );
    final item = action.item;
    final expectedState = phase == RebalanceExecutionPhase.apply
        ? RebalanceExecutionItemState.applying
        : RebalanceExecutionItemState.undoing;
    final now = _now();
    if (action.sessionStatus != RebalanceExecutionSessionStatus.active ||
        item.ownerUserId != ownerUserId ||
        item.state != expectedState ||
        item.attemptToken != attemptToken ||
        item.leaseUntil == null ||
        !item.leaseUntil!.isAfter(now)) {
      _throwStale(itemId);
    }

    final request = item.request;
    if (request == null ||
        item.rawRequestJson == null ||
        request.transactionId != itemId ||
        request.account.sync.ownerUserId != ownerUserId) {
      throw const RebalanceExecutionConflict(
        'Claimed item request does not match the caller and transaction.',
      );
    }
    if (phase == RebalanceExecutionPhase.undo) {
      final receipt = item.receipt;
      if (receipt == null ||
          item.rawReceiptJson == null ||
          item.appliedSequence == null ||
          receipt.transactionId != itemId ||
          receipt.assetAfter.sync.ownerUserId != ownerUserId) {
        throw const RebalanceExecutionConflict(
          'Claimed item receipt does not match the caller and transaction.',
        );
      }
    }
    return item;
  }

  Future<List<RebalanceExecutionItem>> listAppliedForUndo({
    required String ownerUserId,
    required String sessionId,
  }) async {
    _requireOwner(ownerUserId);
    final rows = await _db
        .customSelect(
          'SELECT i.* FROM rebalance_execution_items i '
          'JOIN rebalance_execution_sessions s ON s.id = i.session_id '
          ' AND s.owner_user_id = i.owner_user_id '
          'WHERE i.owner_user_id = ?1 AND i.session_id = ?2 '
          "  AND s.status = 'active' "
          "  AND (i.state IN ('applied', 'undoFailed', 'undoing') "
          "    OR (i.state = 'recoveryBlocked' "
          '      AND i.recovery_was_applied = 1)) '
          'ORDER BY i.applied_sequence DESC',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(sessionId),
          ],
        )
        .get();
    final items = <RebalanceExecutionItem>[];
    for (final row in rows) {
      items.add(await _itemFromRow(row));
    }
    return items;
  }

  Future<RebalanceExecutionAttempt?> _claim({
    required String ownerUserId,
    required String itemId,
    required Duration leaseDuration,
    required RebalanceExecutionPhase phase,
  }) async {
    _requireOwner(ownerUserId);
    if (leaseDuration <= Duration.zero) {
      throw const RebalanceExecutionInvariantError(
        'Lease duration must be positive.',
      );
    }
    final action = await _itemForAction(
      ownerUserId: ownerUserId,
      itemId: itemId,
    );
    if (action.sessionStatus != RebalanceExecutionSessionStatus.active) {
      throw const RebalanceExecutionConflict(
        'Archived session items cannot be claimed.',
      );
    }
    if (action.item.state == RebalanceExecutionItemState.recoveryBlocked) {
      return null;
    }

    final now = _now();
    final leaseUntil = now.add(leaseDuration);
    final token = _uuid.v4();
    final applying = phase == RebalanceExecutionPhase.apply;
    final state = applying ? 'applying' : 'undoing';
    final eligible = applying
        ? "(state IN ('ready', 'applyFailed') OR "
              "(state = 'applying' AND lease_until_iso <= ?2))"
        : "(state IN ('applied', 'undoFailed') OR "
              "(state = 'undoing' AND lease_until_iso <= ?2))";
    final requiredPayload = applying
        ? 'request_json IS NOT NULL AND receipt_json IS NULL '
        : 'request_json IS NOT NULL AND receipt_json IS NOT NULL '
              'AND applied_sequence IS NOT NULL ';
    final undoOrderBarrier = applying
        ? ''
        : 'AND NOT EXISTS ('
              'SELECT 1 FROM rebalance_execution_items blocker '
              'WHERE blocker.session_id = rebalance_execution_items.session_id '
              '  AND blocker.owner_user_id = ?5 '
              '  AND blocker.applied_sequence > '
              '      rebalance_execution_items.applied_sequence '
              "  AND (blocker.state IN ('applied', 'undoFailed', 'undoing') "
              "    OR (blocker.state = 'recoveryBlocked' "
              '      AND blocker.recovery_was_applied = 1))) ';
    final changed = await _db.customUpdate(
      'UPDATE rebalance_execution_items '
      'SET state = \'$state\', attempt_token = ?1, lease_until_iso = ?3, '
      '    error = NULL, updated_at_iso = ?2 '
      'WHERE id = ?4 AND owner_user_id = ?5 AND $eligible '
      '  AND $requiredPayload '
      '  $undoOrderBarrier '
      '  AND EXISTS (SELECT 1 FROM rebalance_execution_sessions s '
      '    WHERE s.id = rebalance_execution_items.session_id '
      '      AND s.owner_user_id = ?5 AND s.status = \'active\')',
      variables: [
        Variable.withString(token),
        Variable.withString(_iso(now)),
        Variable.withString(_iso(leaseUntil)),
        Variable.withString(itemId),
        Variable.withString(ownerUserId),
      ],
    );
    if (changed != 1) return null;
    final item = (await getItem(ownerUserId: ownerUserId, id: itemId))!;
    return RebalanceExecutionAttempt(
      item: item,
      phase: phase,
      token: token,
      leaseUntil: leaseUntil,
    );
  }

  Future<DateTime> _renew({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required Duration leaseDuration,
    required RebalanceExecutionPhase phase,
  }) async {
    _requireOwner(ownerUserId);
    if (leaseDuration <= Duration.zero) {
      throw const RebalanceExecutionInvariantError(
        'Lease duration must be positive.',
      );
    }
    final now = _now();
    final leaseUntil = now.add(leaseDuration);
    final state = phase == RebalanceExecutionPhase.apply
        ? 'applying'
        : 'undoing';
    final changed = await _db.customUpdate(
      'UPDATE rebalance_execution_items '
      'SET lease_until_iso = ?1, updated_at_iso = ?2 '
      'WHERE id = ?3 AND owner_user_id = ?4 AND state = ?5 '
      '  AND attempt_token = ?6 AND lease_until_iso > ?2 '
      '  AND EXISTS (SELECT 1 FROM rebalance_execution_sessions s '
      '    WHERE s.id = rebalance_execution_items.session_id '
      '      AND s.owner_user_id = ?4 AND s.status = \'active\')',
      variables: [
        Variable.withString(_iso(leaseUntil)),
        Variable.withString(_iso(now)),
        Variable.withString(itemId),
        Variable.withString(ownerUserId),
        Variable.withString(state),
        Variable.withString(attemptToken),
      ],
    );
    if (changed != 1) _throwStale(itemId);
    return leaseUntil;
  }

  Future<void> _finishAttempt({
    required String ownerUserId,
    required String itemId,
    required String attemptToken,
    required RebalanceExecutionPhase phase,
    required RebalanceExecutionItemState nextState,
    required String? error,
  }) async {
    _requireOwner(ownerUserId);
    final now = _now();
    final state = phase == RebalanceExecutionPhase.apply
        ? 'applying'
        : 'undoing';
    final changed = await _db.customUpdate(
      'UPDATE rebalance_execution_items '
      'SET state = ?1, error = ?2, attempt_token = NULL, '
      '    lease_until_iso = NULL, updated_at_iso = ?3 '
      'WHERE id = ?4 AND owner_user_id = ?5 AND state = ?6 '
      '  AND attempt_token = ?7 AND lease_until_iso > ?3 '
      '  AND EXISTS (SELECT 1 FROM rebalance_execution_sessions s '
      '    WHERE s.id = rebalance_execution_items.session_id '
      '      AND s.owner_user_id = ?5 AND s.status = \'active\')',
      variables: [
        Variable.withString(nextState.name),
        _nullableStringVariable(error),
        Variable.withString(_iso(now)),
        Variable.withString(itemId),
        Variable.withString(ownerUserId),
        Variable.withString(state),
        Variable.withString(attemptToken),
      ],
    );
    if (changed != 1) _throwStale(itemId);
  }

  Future<
    ({
      RebalanceExecutionItem item,
      RebalanceExecutionSessionStatus sessionStatus,
    })
  >
  _itemForAction({required String ownerUserId, required String itemId}) async {
    final rows = await _db
        .customSelect(
          'SELECT i.*, s.status AS session_status '
          'FROM rebalance_execution_items i '
          'JOIN rebalance_execution_sessions s ON s.id = i.session_id '
          ' AND s.owner_user_id = i.owner_user_id '
          'WHERE i.id = ?1 AND i.owner_user_id = ?2',
          variables: [
            Variable.withString(itemId),
            Variable.withString(ownerUserId),
          ],
        )
        .get();
    if (rows.isEmpty) {
      throw const RebalanceExecutionNotFound('Execution item not found.');
    }
    final row = rows.single;
    return (
      item: await _itemFromRow(row),
      sessionStatus: _sessionStatus(row.read<String>('session_status')),
    );
  }

  Future<RebalanceExecutionSession> _sessionFromRow(QueryRow row) async {
    final owner = row.read<String>('owner_user_id');
    final id = row.read<String>('id');
    final itemRows = await _db
        .customSelect(
          'SELECT * FROM rebalance_execution_items '
          'WHERE session_id = ?1 AND owner_user_id = ?2 ORDER BY position',
          variables: [Variable.withString(id), Variable.withString(owner)],
        )
        .get();
    final items = <RebalanceExecutionItem>[];
    for (final itemRow in itemRows) {
      items.add(await _itemFromRow(itemRow));
    }
    final rawPlan = row.read<String>('plan_json');
    final plan = RebalancePlanCodec.decode(rawPlan);
    final fingerprint = row.read<String>('plan_fingerprint');
    if (fingerprint != RebalancePlanFingerprint.compute(plan)) {
      throw const RebalanceExecutionCodecError(
        'Stored rebalance plan fingerprint does not match its snapshot.',
      );
    }
    return RebalanceExecutionSession(
      id: id,
      ownerUserId: owner,
      status: _sessionStatus(row.read<String>('status')),
      plan: plan,
      rawPlanJson: rawPlan,
      planFingerprint: fingerprint,
      items: items,
      createdAt: _storedDate(row, 'created_at_iso'),
      updatedAt: _storedDate(row, 'updated_at_iso'),
      archivedAt: _storedNullableDate(row, 'archived_at_iso'),
    );
  }

  Future<RebalanceExecutionItem> _itemFromRow(
    QueryRow row, {
    int recoveryRetries = 0,
  }) async {
    final state = _itemState(row.read<String>('state'));
    final rawRequest = row.read<String?>('request_json');
    final rawReceipt = row.read<String?>('receipt_json');
    final recoveryWasApplied = row.read<int>('recovery_was_applied') == 1;
    // A suggestion is the immutable business identity for the item. If its
    // strict snapshot is corrupt there is no honest domain value to invent,
    // so fail closed before attempting any recovery write.
    final suggestion = RebalanceSuggestionCodec.decode(
      row.read<String>('suggestion_json'),
    );
    if (state == RebalanceExecutionItemState.recoveryBlocked) {
      return _recoveryItem(
        row,
        suggestion: suggestion,
        rawRequest: rawRequest,
        rawReceipt: rawReceipt,
        recoveryWasApplied: recoveryWasApplied,
      );
    }

    try {
      final request = rawRequest == null
          ? null
          : RebalanceExecutionRequestCodec.decode(rawRequest);
      final receipt = rawReceipt == null
          ? null
          : TradeMutationReceiptCodec.decode(rawReceipt);
      return RebalanceExecutionItem(
        id: row.read<String>('id'),
        sessionId: row.read<String>('session_id'),
        ownerUserId: row.read<String>('owner_user_id'),
        position: row.read<int>('position'),
        suggestion: suggestion,
        request: request,
        receipt: receipt,
        state: state,
        error: row.read<String?>('error'),
        attemptToken: row.read<String?>('attempt_token'),
        leaseUntil: _storedNullableDate(row, 'lease_until_iso'),
        appliedSequence: row.read<int?>('applied_sequence'),
        rawRequestJson: rawRequest,
        rawReceiptJson: rawReceipt,
        createdAt: _storedDate(row, 'created_at_iso'),
        updatedAt: _storedDate(row, 'updated_at_iso'),
      );
    } on RebalanceExecutionCodecError catch (error) {
      return _recoverUnreadableItem(
        row,
        state: state,
        suggestion: suggestion,
        rawRequest: rawRequest,
        rawReceipt: rawReceipt,
        error: error,
        recoveryRetries: recoveryRetries,
      );
    } on RebalanceExecutionInvariantError catch (error) {
      return _recoverUnreadableItem(
        row,
        state: state,
        suggestion: suggestion,
        rawRequest: rawRequest,
        rawReceipt: rawReceipt,
        error: error,
        recoveryRetries: recoveryRetries,
      );
    }
  }

  Future<RebalanceExecutionItem> _recoverUnreadableItem(
    QueryRow row, {
    required RebalanceExecutionItemState state,
    required SuggestedTrade suggestion,
    required String? rawRequest,
    required String? rawReceipt,
    required Object error,
    required int recoveryRetries,
  }) async {
    final wasApplied = switch (state) {
      RebalanceExecutionItemState.applied ||
      RebalanceExecutionItemState.undoing ||
      RebalanceExecutionItemState.undoFailed => true,
      _ => false,
    };
    final blockedAt = await _blockRecovery(
      row,
      error: error,
      wasApplied: wasApplied,
    );
    if (blockedAt == null) {
      if (recoveryRetries >= 2) {
        throw const RebalanceExecutionConflict(
          'Execution item changed repeatedly during recovery.',
        );
      }
      final latest = await _itemRow(
        ownerUserId: row.read<String>('owner_user_id'),
        id: row.read<String>('id'),
      );
      if (latest == null) {
        throw const RebalanceExecutionConflict(
          'Execution item disappeared during recovery.',
        );
      }
      return _itemFromRow(latest, recoveryRetries: recoveryRetries + 1);
    }
    return _recoveryItem(
      row,
      suggestion: suggestion,
      rawRequest: rawRequest,
      rawReceipt: rawReceipt,
      recoveryWasApplied: wasApplied,
      error: error.toString(),
      updatedAt: blockedAt,
    );
  }

  RebalanceExecutionItem _recoveryItem(
    QueryRow row, {
    required SuggestedTrade suggestion,
    required String? rawRequest,
    required String? rawReceipt,
    required bool recoveryWasApplied,
    String? error,
    DateTime? updatedAt,
  }) => RebalanceExecutionItem(
    id: row.read<String>('id'),
    sessionId: row.read<String>('session_id'),
    ownerUserId: row.read<String>('owner_user_id'),
    position: row.read<int>('position'),
    suggestion: suggestion,
    state: RebalanceExecutionItemState.recoveryBlocked,
    error: error ?? row.read<String?>('error'),
    appliedSequence: row.read<int?>('applied_sequence'),
    rawRequestJson: rawRequest,
    rawReceiptJson: rawReceipt,
    recoveryWasApplied: recoveryWasApplied,
    createdAt: _storedDate(row, 'created_at_iso'),
    updatedAt: updatedAt ?? _storedDate(row, 'updated_at_iso'),
  );

  Future<DateTime?> _blockRecovery(
    QueryRow row, {
    required Object error,
    required bool wasApplied,
  }) async {
    final now = _now();
    final changed = await _db.customUpdate(
      'UPDATE rebalance_execution_items '
      "SET state = 'recoveryBlocked', error = ?1, attempt_token = NULL, "
      '    lease_until_iso = NULL, recovery_was_applied = ?2, '
      '    updated_at_iso = ?3 '
      'WHERE id = ?4 AND owner_user_id = ?5 AND state = ?6 '
      '  AND attempt_token IS ?7 AND lease_until_iso IS ?8 '
      '  AND request_json IS ?9 AND receipt_json IS ?10 '
      '  AND applied_sequence IS ?11 AND updated_at_iso = ?12 '
      '  AND session_id = ?13 AND position = ?14 '
      '  AND suggestion_json = ?15 AND error IS ?16 '
      '  AND recovery_was_applied = ?17 AND created_at_iso = ?18',
      variables: [
        Variable.withString(error.toString()),
        Variable.withInt(wasApplied ? 1 : 0),
        Variable.withString(_iso(now)),
        Variable.withString(row.read<String>('id')),
        Variable.withString(row.read<String>('owner_user_id')),
        Variable.withString(row.read<String>('state')),
        _nullableStringVariable(row.read<String?>('attempt_token')),
        _nullableStringVariable(row.read<String?>('lease_until_iso')),
        _nullableStringVariable(row.read<String?>('request_json')),
        _nullableStringVariable(row.read<String?>('receipt_json')),
        _nullableIntVariable(row.read<int?>('applied_sequence')),
        Variable.withString(row.read<String>('updated_at_iso')),
        Variable.withString(row.read<String>('session_id')),
        Variable.withInt(row.read<int>('position')),
        Variable.withString(row.read<String>('suggestion_json')),
        _nullableStringVariable(row.read<String?>('error')),
        Variable.withInt(row.read<int>('recovery_was_applied')),
        Variable.withString(row.read<String>('created_at_iso')),
      ],
    );
    return changed == 1 ? now : null;
  }

  Future<QueryRow?> _activeSessionRow(String ownerUserId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM rebalance_execution_sessions '
          "WHERE owner_user_id = ?1 AND status = 'active' LIMIT 1",
          variables: [Variable.withString(ownerUserId)],
        )
        .get();
    return rows.isEmpty ? null : rows.single;
  }

  Future<QueryRow?> _itemRow({
    required String ownerUserId,
    required String id,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM rebalance_execution_items '
          'WHERE id = ?1 AND owner_user_id = ?2',
          variables: [
            Variable.withString(id),
            Variable.withString(ownerUserId),
          ],
        )
        .get();
    return rows.isEmpty ? null : rows.single;
  }

  Future<int> _archiveRow({
    required String ownerUserId,
    required String sessionId,
    required DateTime now,
  }) => _db.customUpdate(
    'UPDATE rebalance_execution_sessions '
    "SET status = 'archived', archived_at_iso = ?1, updated_at_iso = ?1 "
    "WHERE id = ?2 AND owner_user_id = ?3 AND status = 'active'",
    variables: [
      Variable.withString(_iso(now)),
      Variable.withString(sessionId),
      Variable.withString(ownerUserId),
    ],
  );

  RebalanceExecutionSessionStatus _sessionStatus(String raw) {
    for (final value in RebalanceExecutionSessionStatus.values) {
      if (value.name == raw) return value;
    }
    throw RebalanceExecutionCodecError('Unknown session status $raw.');
  }

  RebalanceExecutionItemState _itemState(String raw) {
    for (final value in RebalanceExecutionItemState.values) {
      if (value.name == raw) return value;
    }
    throw RebalanceExecutionCodecError('Unknown item state $raw.');
  }

  DateTime _storedDate(QueryRow row, String field) {
    final raw = row.read<String>(field);
    final value = DateTime.tryParse(raw);
    if (!raw.endsWith('Z') || value == null || !value.isUtc) {
      throw RebalanceExecutionCodecError('$field is not a UTC timestamp.');
    }
    return value;
  }

  DateTime? _storedNullableDate(QueryRow row, String field) {
    final raw = row.read<String?>(field);
    if (raw == null) return null;
    final value = DateTime.tryParse(raw);
    if (!raw.endsWith('Z') || value == null || !value.isUtc) {
      throw RebalanceExecutionCodecError('$field is not a UTC timestamp.');
    }
    return value;
  }

  DateTime _now() {
    final value = _clock();
    if (!value.isUtc) {
      throw const RebalanceExecutionInvariantError('Clock must return UTC.');
    }
    return value;
  }

  static DateTime _utcNow() => DateTime.now().toUtc();

  static String _iso(DateTime value) => value.toIso8601String();

  static Variable<String> _nullableStringVariable(String? value) =>
      value == null ? const Variable<String>(null) : Variable.withString(value);

  static Variable<int> _nullableIntVariable(int? value) =>
      value == null ? const Variable<int>(null) : Variable.withInt(value);

  static void _requireOwner(String ownerUserId) {
    if (ownerUserId.isEmpty) {
      throw const RebalanceExecutionInvariantError(
        'ownerUserId must not be empty.',
      );
    }
  }

  Never _throwStale(String itemId) {
    throw RebalanceStaleAttempt(
      'Attempt for item $itemId is stale, expired, or no longer active.',
    );
  }
}
