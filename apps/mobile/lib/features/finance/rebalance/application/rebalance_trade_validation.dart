import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import '../domain/rebalance_execution.dart';
import '../domain/rebalance_models.dart';

enum RebalanceTradeValidationCode {
  missingRequest,
  identityMismatch,
  directionMismatch,
  assetTargetMismatch,
  categoryMismatch,
  unsupportedAsset,
  ownerMismatch,
  accountInvalid,
  cashAccountInvalid,
  assetInvalid,
  staleSnapshot,
}

final class RebalanceTradeValidationError implements Exception {
  const RebalanceTradeValidationError(this.code, this.message);

  final RebalanceTradeValidationCode code;
  final String message;

  @override
  String toString() => 'RebalanceTradeValidationError(${code.name}): $message';
}

final class RebalanceTradeValidation {
  const RebalanceTradeValidation(this._db);

  final AppDatabase _db;

  bool isBoundTo(AppDatabase database) => identical(_db, database);

  TradeEntrySubmissionRequest validateSnapshot(RebalanceExecutionItem item) {
    final request = item.request;
    if (request == null) {
      throw const RebalanceTradeValidationError(
        RebalanceTradeValidationCode.missingRequest,
        'Execution item has no reviewed request.',
      );
    }
    return validateReviewedRequest(item, request);
  }

  TradeEntrySubmissionRequest validateReviewedRequest(
    RebalanceExecutionItem item,
    RebalanceExecutionRequest request,
  ) {
    if (item.id != request.transactionId) {
      throw const RebalanceTradeValidationError(
        RebalanceTradeValidationCode.identityMismatch,
        'Execution item and request transaction ids differ.',
      );
    }
    final expectedType = item.suggestion.direction == TradeDirection.buy
        ? TradeType.buy
        : TradeType.sell;
    if (request.type != expectedType) {
      throw const RebalanceTradeValidationError(
        RebalanceTradeValidationCode.directionMismatch,
        'Suggested direction and reviewed trade type differ.',
      );
    }
    final targetAssetId = item.suggestion.assetId;
    if (targetAssetId != null &&
        (targetAssetId.isEmpty || targetAssetId != request.asset.id)) {
      throw const RebalanceTradeValidationError(
        RebalanceTradeValidationCode.assetTargetMismatch,
        'Suggested asset target and reviewed asset differ.',
      );
    }
    if (categoryForAssetType(request.asset.type) != item.suggestion.category) {
      throw const RebalanceTradeValidationError(
        RebalanceTradeValidationCode.categoryMismatch,
        'Suggested category and reviewed asset type differ.',
      );
    }
    if (!kSecuritiesAssetTypes.contains(request.asset.type)) {
      throw const RebalanceTradeValidationError(
        RebalanceTradeValidationCode.unsupportedAsset,
        'Rebalance execution supports tradable securities only.',
      );
    }
    final market = assetMarketFromWire(request.asset.market);
    if (request.asset.id.isEmpty ||
        request.asset.symbol.trim().isEmpty ||
        request.asset.symbol.contains(':') ||
        market == null ||
        market == AssetMarket.unknown ||
        request.asset.market != market.wire ||
        request.asset.id != Asset.idFor(market, request.asset.symbol)) {
      throw const RebalanceTradeValidationError(
        RebalanceTradeValidationCode.assetInvalid,
        'Reviewed asset market and deterministic id are not canonical.',
      );
    }
    final owner = item.ownerUserId;
    if (owner.isEmpty ||
        request.account.sync.ownerUserId != owner ||
        request.asset.sync.ownerUserId != owner ||
        request.cashAccount != null &&
            request.cashAccount!.sync.ownerUserId != owner) {
      throw const RebalanceTradeValidationError(
        RebalanceTradeValidationCode.ownerMismatch,
        'Reviewed account and asset snapshots must share the item owner.',
      );
    }
    _validateAccountSnapshot(request.account, primary: true);
    final cash = request.cashAccount;
    if (cash != null) _validateAccountSnapshot(cash, primary: false);
    final effectiveCash = cash ?? request.account;
    if (const {
          AccountCategory.cash,
          AccountCategory.bank,
        }.contains(effectiveCash.type) &&
        effectiveCash.currency.toUpperCase() !=
            request.currency.toUpperCase()) {
      throw const RebalanceTradeValidationError(
        RebalanceTradeValidationCode.cashAccountInvalid,
        'Reviewed cash account currency does not match the trade.',
      );
    }
    return TradeEntrySubmissionRequest(
      transactionId: request.transactionId,
      symbol: request.asset.symbol,
      market: market,
      assetType: request.asset.type,
      assetCurrency: request.asset.currency,
      assetName: request.asset.name,
      isin: request.asset.isin,
      type: request.type,
      accountId: request.account.id,
      cashAccountId: request.cashAccount?.id,
      quantity: request.quantity,
      price: request.price,
      currency: request.currency,
      tradeDate: request.tradeDate,
      fee: request.fee?.sign == 0 ? null : request.fee,
      tax: request.tax?.sign == 0 ? null : request.tax,
      note: request.note,
      defaultNarration: (asset) =>
          '${request.type.name} ${request.quantity} ${asset.symbol}',
    );
  }

  Future<void> validateFresh(
    AppDatabaseTransactionScope scope,
    RebalanceExecutionItem claimed,
  ) async {
    scope.requireDatabase(_db);
    final request = claimed.request;
    if (request == null) {
      throw const RebalanceTradeValidationError(
        RebalanceTradeValidationCode.missingRequest,
        'Execution item has no reviewed request.',
      );
    }
    validateReviewedRequest(claimed, request);
    await validateReviewedSnapshotsFresh(
      scope,
      ownerUserId: claimed.ownerUserId,
      request: request,
    );
  }

  Future<void> validateReviewedSnapshotsFresh(
    AppDatabaseTransactionScope scope, {
    required String ownerUserId,
    required RebalanceExecutionRequest request,
  }) async {
    scope.requireDatabase(_db);
    final primary = await _accountRow(request.account.id, ownerUserId);
    if (primary == null || !_sameAccount(primary, request.account)) {
      _throwStale('The reviewed primary account changed or is no longer live.');
    }
    final reviewedCash = request.cashAccount;
    if (reviewedCash != null) {
      final cash = await _accountRow(reviewedCash.id, ownerUserId);
      if (cash == null || !_sameAccount(cash, reviewedCash)) {
        _throwStale('The reviewed cash account changed or is no longer live.');
      }
    }
    final asset = await _assetRow(request.asset.id, ownerUserId);
    if (asset == null || !_sameAsset(asset, request.asset)) {
      _throwStale('The reviewed security changed or is no longer live.');
    }
  }

  Future<AccountRow?> _accountRow(String id, String owner) =>
      (_db.select(_db.accounts)
            ..where((row) => row.id.equals(id))
            ..where((row) => row.ownerUserId.equals(owner)))
          .getSingleOrNull();

  Future<AssetRow?> _assetRow(String id, String owner) =>
      (_db.select(_db.assets)
            ..where((row) => row.id.equals(id))
            ..where((row) => row.ownerUserId.equals(owner)))
          .getSingleOrNull();

  bool _sameAccount(AccountRow row, Account reviewed) =>
      row.deletedAt == null &&
      !row.archived &&
      reviewed.sync.deletedAt == null &&
      reviewed.sync.updatedAt.isUtc &&
      row.id == reviewed.id &&
      row.type == reviewed.type &&
      row.name == reviewed.name &&
      row.currency == reviewed.currency &&
      row.institution == reviewed.institution &&
      row.accountNumber == reviewed.accountNumber &&
      row.note == reviewed.note &&
      row.archived == reviewed.archived &&
      row.category == reviewed.category &&
      row.parentId == reviewed.parentId &&
      row.icon == reviewed.icon &&
      row.color == reviewed.color &&
      row.ownerUserId == reviewed.sync.ownerUserId &&
      row.updatedAt.toUtc() == reviewed.sync.updatedAt &&
      row.updatedByDevice == reviewed.sync.updatedByDevice &&
      row.hlc == reviewed.sync.hlc;

  bool _sameAsset(AssetRow row, Asset reviewed) =>
      row.deletedAt == null &&
      reviewed.sync.deletedAt == null &&
      reviewed.sync.updatedAt.isUtc &&
      row.id == reviewed.id &&
      row.type == reviewed.type &&
      row.symbol == reviewed.symbol &&
      row.currency == reviewed.currency &&
      row.name == reviewed.name &&
      row.market == reviewed.market &&
      row.industry == reviewed.industry &&
      row.region == reviewed.region &&
      row.isin == reviewed.isin &&
      row.logoUrl == reviewed.logoUrl &&
      row.metadataJson == reviewed.metadataJson &&
      row.ownerUserId == reviewed.sync.ownerUserId &&
      row.updatedAt.toUtc() == reviewed.sync.updatedAt &&
      row.updatedByDevice == reviewed.sync.updatedByDevice &&
      row.hlc == reviewed.sync.hlc;

  Never _throwStale(String message) {
    throw RebalanceTradeValidationError(
      RebalanceTradeValidationCode.staleSnapshot,
      message,
    );
  }

  void _validateAccountSnapshot(Account account, {required bool primary}) {
    final allowed = primary
        ? const {AccountCategory.broker, AccountCategory.crypto}
        : const {
            AccountCategory.cash,
            AccountCategory.bank,
            AccountCategory.broker,
            AccountCategory.crypto,
          };
    if (account.archived ||
        account.sync.deletedAt != null ||
        account.category != AccountSide.asset ||
        !allowed.contains(account.type)) {
      throw RebalanceTradeValidationError(
        primary
            ? RebalanceTradeValidationCode.accountInvalid
            : RebalanceTradeValidationCode.cashAccountInvalid,
        'Reviewed ${primary ? 'primary' : 'cash'} account is not tradable.',
      );
    }
  }
}
