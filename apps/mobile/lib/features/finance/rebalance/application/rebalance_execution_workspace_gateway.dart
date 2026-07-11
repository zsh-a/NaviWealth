import 'package:naviwealth/core/persistence/app_database.dart';

import '../data/rebalance_execution_store.dart';
import '../domain/rebalance_execution.dart';
import '../domain/rebalance_models.dart';
import 'rebalance_execution_coordinator.dart';
import 'rebalance_trade_validation.dart';

abstract interface class RebalanceExecutionWorkspaceGateway {
  Future<RebalanceExecutionSession?> active();

  Future<RebalanceExecutionSession?> session(String sessionId);

  Future<RebalanceExecutionSession> createOrResume(RebalancePlan plan);

  Future<RebalanceExecutionSession> replaceActive({
    required String expectedSessionId,
    required String expectedFingerprint,
    required RebalancePlan plan,
  });

  Future<RebalanceExecutionItem> saveReviewedRequest({
    required RebalanceExecutionItem expected,
    required RebalanceExecutionRequest request,
  });

  Future<RebalanceExecutionItem> skip(String itemId);

  Future<RebalanceExecutionItem> reopen(String itemId);

  Future<void> archive(String sessionId);

  Future<RebalanceExecutionBatchResult> apply(
    String sessionId, {
    List<String>? itemIds,
    RebalanceStopSignal stop = const NeverRebalanceStopSignal(),
  });

  Future<RebalanceExecutionBatchResult> undo(
    String sessionId, {
    List<String>? itemIds,
    RebalanceStopSignal stop = const NeverRebalanceStopSignal(),
  });
}

final class DefaultRebalanceExecutionWorkspaceGateway
    implements RebalanceExecutionWorkspaceGateway {
  DefaultRebalanceExecutionWorkspaceGateway({
    required AppDatabase db,
    required RebalanceExecutionStore store,
    required RebalanceTradeValidation validation,
    required RebalanceExecutionCoordinator coordinator,
    required Future<String> Function() currentUserId,
  }) : _db = db,
       _store = store,
       _validation = validation,
       _coordinator = coordinator,
       _currentUserId = currentUserId {
    if (!store.isBoundTo(db) ||
        !validation.isBoundTo(db) ||
        !coordinator.isBoundTo(db)) {
      throw const RebalanceExecutionInvariantError(
        'Workspace gateway dependencies must share one AppDatabase.',
      );
    }
  }

  final AppDatabase _db;
  final RebalanceExecutionStore _store;
  final RebalanceTradeValidation _validation;
  final RebalanceExecutionCoordinator _coordinator;
  final Future<String> Function() _currentUserId;

  bool isBoundTo(AppDatabase database) => identical(_db, database);

  @override
  Future<RebalanceExecutionSession?> active() async {
    final owner = await _currentUserId();
    return _store.getActive(owner);
  }

  @override
  Future<RebalanceExecutionSession?> session(String sessionId) async {
    final owner = await _currentUserId();
    return _store.getSession(ownerUserId: owner, id: sessionId);
  }

  @override
  Future<RebalanceExecutionSession> createOrResume(RebalancePlan plan) async {
    final owner = await _currentUserId();
    return _store.createOrResume(ownerUserId: owner, plan: plan);
  }

  @override
  Future<RebalanceExecutionSession> replaceActive({
    required String expectedSessionId,
    required String expectedFingerprint,
    required RebalancePlan plan,
  }) async {
    final owner = await _currentUserId();
    await _requireSession(owner, expectedSessionId);
    return _store.replaceActive(
      ownerUserId: owner,
      expectedSessionId: expectedSessionId,
      expectedFingerprint: expectedFingerprint,
      plan: plan,
    );
  }

  @override
  Future<RebalanceExecutionItem> saveReviewedRequest({
    required RebalanceExecutionItem expected,
    required RebalanceExecutionRequest request,
  }) async {
    final owner = await _currentUserId();
    return _db.transactionWithScope((scope) async {
      if (expected.ownerUserId != owner) _throwItemNotFound();
      final item = await _store.getItem(ownerUserId: owner, id: expected.id);
      if (item == null) _throwItemNotFound();
      if (item.state != expected.state ||
          item.updatedAt != expected.updatedAt ||
          item.rawRequestJson != expected.rawRequestJson) {
        throw const RebalanceExecutionConflict(
          'Execution item changed after this review was opened.',
        );
      }
      _validation.validateReviewedRequest(item, request);
      await _validation.validateReviewedSnapshotsFresh(
        scope,
        ownerUserId: owner,
        request: request,
      );
      return _store.saveRequest(
        ownerUserId: owner,
        expected: expected,
        request: request,
      );
    });
  }

  @override
  Future<RebalanceExecutionItem> skip(String itemId) async {
    final owner = await _currentUserId();
    await _requireItem(owner, itemId);
    return _store.markSkipped(ownerUserId: owner, itemId: itemId);
  }

  @override
  Future<RebalanceExecutionItem> reopen(String itemId) async {
    final owner = await _currentUserId();
    await _requireItem(owner, itemId);
    return _store.reopenSkipped(ownerUserId: owner, itemId: itemId);
  }

  @override
  Future<void> archive(String sessionId) async {
    final owner = await _currentUserId();
    await _requireSession(owner, sessionId);
    await _store.archive(ownerUserId: owner, sessionId: sessionId);
  }

  @override
  Future<RebalanceExecutionBatchResult> apply(
    String sessionId, {
    List<String>? itemIds,
    RebalanceStopSignal stop = const NeverRebalanceStopSignal(),
  }) async {
    final owner = await _currentUserId();
    await _requireSession(owner, sessionId);
    return _coordinator.applySession(
      sessionId: sessionId,
      itemIds: itemIds,
      stop: stop,
    );
  }

  @override
  Future<RebalanceExecutionBatchResult> undo(
    String sessionId, {
    List<String>? itemIds,
    RebalanceStopSignal stop = const NeverRebalanceStopSignal(),
  }) async {
    final owner = await _currentUserId();
    await _requireSession(owner, sessionId);
    return _coordinator.undoSession(
      sessionId: sessionId,
      itemIds: itemIds,
      stop: stop,
    );
  }

  Future<RebalanceExecutionSession> _requireSession(
    String owner,
    String sessionId,
  ) async {
    final value = await _store.getSession(ownerUserId: owner, id: sessionId);
    if (value == null) {
      throw const RebalanceExecutionNotFound('Execution session not found.');
    }
    return value;
  }

  Future<RebalanceExecutionItem> _requireItem(
    String owner,
    String itemId,
  ) async {
    final value = await _store.getItem(ownerUserId: owner, id: itemId);
    if (value == null) _throwItemNotFound();
    return value;
  }

  Never _throwItemNotFound() {
    throw const RebalanceExecutionNotFound('Execution item not found.');
  }
}
