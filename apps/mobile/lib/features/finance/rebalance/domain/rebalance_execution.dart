import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';

import 'rebalance_models.dart';

enum RebalanceExecutionSessionStatus { active, archived }

enum RebalanceExecutionItemState {
  needsDetails,
  ready,
  applying,
  applied,
  applyFailed,
  undoing,
  undone,
  undoFailed,
  skipped,
  recoveryBlocked,
}

enum RebalanceExecutionPhase { apply, undo }

/// Callback-free, strictly serializable input for Commit 2's trade mapper.
final class RebalanceExecutionRequest {
  const RebalanceExecutionRequest({
    required this.transactionId,
    required this.account,
    required this.asset,
    required this.type,
    required this.quantity,
    required this.currency,
    required this.tradeDate,
    this.cashAccount,
    this.price,
    this.fee,
    this.tax,
    this.note,
  });

  final String transactionId;
  final Account account;
  final Account? cashAccount;
  final Asset asset;
  final TradeType type;
  final Decimal quantity;
  final Decimal? price;
  final String currency;
  final DateTime tradeDate;
  final Decimal? fee;
  final Decimal? tax;
  final String? note;

  @override
  bool operator ==(Object other) =>
      other is RebalanceExecutionRequest &&
      other.transactionId == transactionId &&
      other.account == account &&
      other.cashAccount == cashAccount &&
      other.asset == asset &&
      other.type == type &&
      other.quantity == quantity &&
      other.price == price &&
      other.currency == currency &&
      other.tradeDate == tradeDate &&
      other.fee == fee &&
      other.tax == tax &&
      other.note == note;

  @override
  int get hashCode => Object.hash(
    transactionId,
    account,
    cashAccount,
    asset,
    type,
    quantity,
    price,
    currency,
    tradeDate,
    fee,
    tax,
    note,
  );
}

final class RebalanceExecutionItem {
  RebalanceExecutionItem({
    required this.id,
    required this.sessionId,
    required this.ownerUserId,
    required this.position,
    required this.suggestion,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.request,
    this.receipt,
    this.error,
    this.attemptToken,
    this.leaseUntil,
    this.appliedSequence,
    this.rawRequestJson,
    this.rawReceiptJson,
    this.recoveryWasApplied = false,
  }) {
    _validate();
  }

  final String id;
  final String sessionId;
  final String ownerUserId;
  final int position;
  final SuggestedTrade suggestion;
  final RebalanceExecutionRequest? request;
  final TradeMutationReceipt? receipt;
  final RebalanceExecutionItemState state;
  final String? error;
  final String? attemptToken;
  final DateTime? leaseUntil;
  final int? appliedSequence;
  final String? rawRequestJson;
  final String? rawReceiptJson;
  final bool recoveryWasApplied;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isResolved => switch (state) {
    RebalanceExecutionItemState.applied ||
    RebalanceExecutionItemState.undone ||
    RebalanceExecutionItemState.skipped => true,
    _ => false,
  };

  bool get isEconomicallyApplied => switch (state) {
    RebalanceExecutionItemState.applied ||
    RebalanceExecutionItemState.undoing ||
    RebalanceExecutionItemState.undoFailed => true,
    RebalanceExecutionItemState.recoveryBlocked => recoveryWasApplied,
    _ => false,
  };

  void _validate() {
    if (id.isEmpty ||
        sessionId.isEmpty ||
        ownerUserId.isEmpty ||
        position < 0) {
      throw const RebalanceExecutionInvariantError(
        'Execution identity and position must be valid.',
      );
    }
    _requireUtc(createdAt, 'createdAt');
    _requireUtc(updatedAt, 'updatedAt');
    if (request != null && request!.transactionId != id) {
      throw const RebalanceExecutionInvariantError(
        'Request transactionId must equal the item id.',
      );
    }
    if (receipt != null && receipt!.transactionId != id) {
      throw const RebalanceExecutionInvariantError(
        'Receipt transactionId must equal the item id.',
      );
    }
    final leased = attemptToken != null || leaseUntil != null;
    if ((attemptToken == null) != (leaseUntil == null)) {
      throw const RebalanceExecutionInvariantError(
        'Attempt token and lease must appear together.',
      );
    }
    if (leaseUntil != null) _requireUtc(leaseUntil!, 'leaseUntil');

    switch (state) {
      case RebalanceExecutionItemState.needsDetails:
        _require(request == null && receipt == null && appliedSequence == null);
        _require(!leased);
      case RebalanceExecutionItemState.ready:
      case RebalanceExecutionItemState.applyFailed:
        _require(request != null && receipt == null && appliedSequence == null);
        _require(!leased);
      case RebalanceExecutionItemState.applying:
        _require(request != null && receipt == null && appliedSequence == null);
        _require(leased);
      case RebalanceExecutionItemState.applied:
      case RebalanceExecutionItemState.undone:
      case RebalanceExecutionItemState.undoFailed:
        _require(request != null && receipt != null && appliedSequence != null);
        _require(!leased);
      case RebalanceExecutionItemState.undoing:
        _require(request != null && receipt != null && appliedSequence != null);
        _require(leased);
      case RebalanceExecutionItemState.skipped:
        _require(receipt == null && appliedSequence == null);
        _require(!leased);
      case RebalanceExecutionItemState.recoveryBlocked:
        _require(!leased);
        if (recoveryWasApplied) _require(appliedSequence != null);
    }
  }

  void _require(bool condition) {
    if (!condition) {
      throw RebalanceExecutionInvariantError(
        'Invalid persisted fields for item state ${state.name}.',
      );
    }
  }
}

final class RebalanceExecutionSession {
  RebalanceExecutionSession({
    required this.id,
    required this.ownerUserId,
    required this.status,
    required this.plan,
    required this.rawPlanJson,
    required this.planFingerprint,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  }) {
    if (id.isEmpty ||
        ownerUserId.isEmpty ||
        items.any((i) => i.sessionId != id || i.ownerUserId != ownerUserId)) {
      throw const RebalanceExecutionInvariantError(
        'Session and item ownership must match.',
      );
    }
    if (items.map((i) => i.position).toSet().length != items.length) {
      throw const RebalanceExecutionInvariantError(
        'Session item positions must be unique.',
      );
    }
    _requireUtc(createdAt, 'createdAt');
    _requireUtc(updatedAt, 'updatedAt');
    if (archivedAt != null) _requireUtc(archivedAt!, 'archivedAt');
    if ((status == RebalanceExecutionSessionStatus.archived) !=
        (archivedAt != null)) {
      throw const RebalanceExecutionInvariantError(
        'Only archived sessions may have archivedAt.',
      );
    }
  }

  final String id;
  final String ownerUserId;
  final RebalanceExecutionSessionStatus status;
  final RebalancePlan plan;
  final String rawPlanJson;
  final String planFingerprint;
  final List<RebalanceExecutionItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;

  bool get isComplete => items.every((item) => item.isResolved);
}

final class RebalanceExecutionAttempt {
  const RebalanceExecutionAttempt({
    required this.item,
    required this.phase,
    required this.token,
    required this.leaseUntil,
  });

  final RebalanceExecutionItem item;
  final RebalanceExecutionPhase phase;
  final String token;
  final DateTime leaseUntil;
}

final class RebalanceExecutionCodecError implements Exception {
  const RebalanceExecutionCodecError(this.message);

  final String message;

  @override
  String toString() => 'RebalanceExecutionCodecError: $message';
}

final class RebalanceExecutionInvariantError implements Exception {
  const RebalanceExecutionInvariantError(this.message);

  final String message;

  @override
  String toString() => 'RebalanceExecutionInvariantError: $message';
}

final class RebalanceExecutionConflict implements Exception {
  const RebalanceExecutionConflict(this.message);

  final String message;

  @override
  String toString() => 'RebalanceExecutionConflict: $message';
}

final class RebalanceExecutionNotFound implements Exception {
  const RebalanceExecutionNotFound(this.message);

  final String message;

  @override
  String toString() => 'RebalanceExecutionNotFound: $message';
}

final class RebalanceStaleAttempt implements Exception {
  const RebalanceStaleAttempt(this.message);

  final String message;

  @override
  String toString() => 'RebalanceStaleAttempt: $message';
}

void _requireUtc(DateTime value, String field) {
  if (!value.isUtc) {
    throw RebalanceExecutionInvariantError('$field must be UTC.');
  }
}
