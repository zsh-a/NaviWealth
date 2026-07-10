import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_mutation_receipt.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_plan.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import '../data/ledger_lot_reader.dart';

/// Persists a planned trade into ledger entries and price observations.
///
/// [TradeEntryService] stays pure and returns a [TradeEntryPlan]. This
/// application service owns the impure write-through into assets,
/// journal_entries/postings, and prices so UI surfaces don't duplicate
/// ledger construction details.
class TradeEntrySubmissionService {
  TradeEntrySubmissionService({
    required AppDatabase db,
    required SecuritiesAssetRepository securitiesRepo,
    required TradeEntryService tradeService,
    required JournalEntryRepository journalEntryRepo,
    required PriceRepository priceRepo,
    required Future<String> Function() currentUserId,
  }) : _db = db,
       _securitiesRepo = securitiesRepo,
       _tradeService = tradeService,
       _journalEntryRepo = journalEntryRepo,
       _priceRepo = priceRepo,
       _currentUserId = currentUserId,
       _lotReader = LedgerLotReader(db) {
    _requireDatabaseBindings();
  }

  final AppDatabase _db;
  final SecuritiesAssetRepository _securitiesRepo;
  final TradeEntryService _tradeService;
  final JournalEntryRepository _journalEntryRepo;
  final PriceRepository _priceRepo;
  final Future<String> Function() _currentUserId;
  final LedgerLotReader _lotReader;

  bool isBoundTo(AppDatabase database) =>
      identical(_db, database) &&
      _securitiesRepo.isBoundTo(database) &&
      _journalEntryRepo.isBoundTo(database) &&
      _priceRepo.isBoundTo(database) &&
      _lotReader.isBoundTo(database);

  Future<Decimal> balanceByAccountUnit(String accountId, String unit) {
    return _journalEntryRepo.balanceByAccountUnit(accountId, unit);
  }

  /// Resolves every external/domain dependency without opening a DB write.
  Future<PreparedTradeSubmission> prepare(
    TradeEntrySubmissionRequest request,
  ) async {
    _requireDatabaseBindings();
    _requireRequestIdentity(request);
    final uid = await _currentUserId();
    _requireOwner(uid);
    final asset = _assetInput(request, uid);
    final previewLots = request.type == TradeType.sell
        ? await _lotReader.lotsAt(
            ownerUserId: uid,
            accountId: request.accountId,
            assetId: asset.id,
            asOf: request.tradeDate.toUtc(),
          )
        : const <Lot>[];
    final plan = await _tradeService.buildPlan(
      _draft(request: request, asset: asset, price: request.price),
      openLots: previewLots,
    );
    _requireExactPlan(
      plan: plan,
      request: request,
      assetId: asset.id,
      expectedPrice: request.price,
      openLots: previewLots,
    );
    return PreparedTradeSubmission(
      ownerUserId: uid,
      transactionId: request.transactionId,
      request: request,
      assetInput: asset,
      frozenPrice: plan.trade.price,
      priceProvenance: plan.pricing,
      priceSource: request.type == TradeType.valuationAdjust
          ? 'manual'
          : 'trade',
    );
  }

  /// Commits security metadata, ledger rows, price, and outbox atomically.
  Future<TradeMutationReceipt> commit(PreparedTradeSubmission prepared) async {
    final currentOwner = await _currentUserId();
    if (currentOwner != prepared.ownerUserId) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.ownerChanged,
        'Current owner changed after trade preparation.',
      );
    }
    return _db.transactionWithScope(
      (scope) => commitInTransaction(scope, prepared),
    );
  }

  Future<TradeMutationReceipt> commitInTransaction(
    AppDatabaseTransactionScope scope,
    PreparedTradeSubmission prepared,
  ) async {
    scope.requireDatabase(_db);
    _requireDatabaseBindings();
    final uid = prepared.ownerUserId;
    _requireOwner(uid);
    final request = prepared.request;
    _requirePreparedContract(prepared);
    await _validateLiveAccounts(request, uid);
    await _validateExistingAsset(request, prepared.assetInput.id, uid);

    final freshLots = request.type == TradeType.sell
        ? await _freshSellLots(request, prepared.assetInput.id, uid)
        : const <Lot>[];
    final plan = await _tradeService.buildPlan(
      _draft(
        request: request,
        asset: prepared.assetInput,
        price: prepared.frozenPrice,
      ),
      openLots: freshLots,
    );
    _requireExactPlan(
      plan: plan,
      request: request,
      assetId: prepared.assetInput.id,
      expectedPrice: prepared.frozenPrice,
      openLots: freshLots,
    );
    if (plan.pricing.wasBackfilled) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.externalResolutionInTransaction,
        'Final plan attempted external price resolution.',
      );
    }
    final journal = _withEntryId(
      _journalBuild(request, prepared.assetInput, plan, uid),
      prepared.transactionId,
    );
    if (journal.entry.id != prepared.transactionId) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.identityMismatch,
        'Journal entry id must equal transaction id.',
      );
    }

    final assetAfter = await _securitiesRepo.upsertSecurity(
      symbol: prepared.assetInput.symbol,
      market: request.market,
      type: request.assetType,
      currency: request.assetCurrency,
      name: request.assetName,
      isin: request.isin,
    );
    if (assetAfter.id != prepared.assetInput.id ||
        assetAfter.sync.ownerUserId != uid ||
        assetAfter.sync.deletedAt != null) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.assetInvalid,
        'Committed asset does not match the prepared live asset.',
      );
    }
    final journalReceipt = await _journalEntryRepo.createWithReceipt(
      entry: journal.entry,
      postings: journal.postings,
    );
    final tx = plan.trade;
    final priceReceipt = await _priceRepo.upsertWithReceipt(
      id: prepared.transactionId,
      unit: tx.assetId,
      quoteCurrency: tx.currency,
      observedOn: tx.tradeDate,
      perUnit: tx.price,
      source: prepared.priceSource,
    );
    final receipt = TradeMutationReceipt(
      transactionId: prepared.transactionId,
      assetAfter: assetAfter,
      journal: journalReceipt,
      price: priceReceipt,
    );
    _requireReceiptIdentity(receipt, prepared.transactionId);
    return receipt;
  }

  Future<TradeMutationReceipt> submit(
    TradeEntrySubmissionRequest request,
  ) async {
    final prepared = await prepare(request);
    return commit(prepared);
  }

  /// Reverses price + journal atomically while preserving security metadata.
  Future<void> undoMutation(TradeMutationReceipt receipt) async {
    await _db.transactionWithScope(
      (scope) => undoInTransaction(scope, receipt),
    );
  }

  Future<void> undoInTransaction(
    AppDatabaseTransactionScope scope,
    TradeMutationReceipt receipt,
  ) async {
    scope.requireDatabase(_db);
    _requireDatabaseBindings();
    _requireReceiptIdentity(receipt, receipt.transactionId);
    // Every conflict check must complete before either repository writes.
    await _journalEntryRepo.validateUndo(receipt.journal);
    final price = receipt.price;
    if (price != null) await _priceRepo.validateUndo(price);

    if (price != null) await _priceRepo.undoMutation(price);
    await _journalEntryRepo.undoMutation(receipt.journal);
  }

  TradeDraft _draft({
    required TradeEntrySubmissionRequest request,
    required Asset asset,
    required Decimal? price,
  }) => TradeDraft(
    type: request.type,
    asset: asset,
    accountId: request.accountId,
    quantity: request.quantity,
    price: price,
    currency: request.currency,
    tradeDate: request.tradeDate,
    fee: request.fee,
    tax: request.tax,
    note: request.note,
    transactionId: request.transactionId,
  );

  Future<List<Lot>> _freshSellLots(
    TradeEntrySubmissionRequest request,
    String assetId,
    String ownerUserId,
  ) async {
    final tradeAt = request.tradeDate.toUtc();
    final latest = await _lotReader.latestRelevantMovementAt(
      ownerUserId: ownerUserId,
      accountId: request.accountId,
      assetId: assetId,
    );
    if (latest != null && latest.isAfter(tradeAt)) {
      throw TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.backdatedSell,
        'Sell date ${tradeAt.toIso8601String()} precedes the latest live '
        'ledger movement ${latest.toIso8601String()}.',
      );
    }
    final lots = await _lotReader.lotsAt(
      ownerUserId: ownerUserId,
      accountId: request.accountId,
      assetId: assetId,
      asOf: tradeAt,
    );
    if (lots.any(
      (lot) =>
          !lot.isClosed &&
          lot.currency.toUpperCase() != request.currency.toUpperCase(),
    )) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.lotCurrencyMismatch,
        'Open lots must match the trade currency before they can be closed.',
      );
    }
    final lotBalance = lots
        .where((lot) => !lot.isClosed)
        .fold<Decimal>(Decimal.zero, (sum, lot) => sum + lot.remainingQuantity);
    final ledgerBalance = await _lotReader.currentBalance(
      ownerUserId: ownerUserId,
      accountId: request.accountId,
      assetId: assetId,
    );
    if (lotBalance < request.quantity || ledgerBalance < request.quantity) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.insufficientFreshHoldings,
        'Fresh ledger holdings are insufficient for this sell.',
      );
    }
    return lots;
  }

  Future<void> _validateLiveAccounts(
    TradeEntrySubmissionRequest request,
    String ownerUserId,
  ) async {
    final primary = await _liveAccount(request.accountId, ownerUserId);
    if (primary == null ||
        primary.category != AccountSide.asset ||
        !const {
          AccountCategory.broker,
          AccountCategory.crypto,
        }.contains(primary.type)) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.accountInvalid,
        'Primary account must be a live owned broker or crypto account.',
      );
    }
    final cashId = request.cashAccountId;
    final cash = cashId == null
        ? primary
        : await _liveAccount(cashId, ownerUserId);
    if (cash == null ||
        cash.category != AccountSide.asset ||
        !const {
          AccountCategory.cash,
          AccountCategory.bank,
          AccountCategory.broker,
          AccountCategory.crypto,
        }.contains(cash.type) ||
        const {
              AccountCategory.cash,
              AccountCategory.bank,
            }.contains(cash.type) &&
            cash.currency.toUpperCase() != request.currency.toUpperCase()) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.cashAccountInvalid,
        'Cash account must be live, owned, asset-side, and match currency.',
      );
    }
  }

  Future<AccountRow?> _liveAccount(String id, String ownerUserId) =>
      (_db.select(_db.accounts)
            ..where((row) => row.id.equals(id))
            ..where((row) => row.ownerUserId.equals(ownerUserId))
            ..where((row) => row.deletedAt.isNull())
            ..where((row) => row.archived.equals(false)))
          .getSingleOrNull();

  Future<void> _validateExistingAsset(
    TradeEntrySubmissionRequest request,
    String assetId,
    String ownerUserId,
  ) async {
    final canonicalId = Asset.idFor(request.market, request.symbol);
    if (assetId != canonicalId) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.assetInvalid,
        'Prepared asset id is not canonical for market and symbol.',
      );
    }
    final existing = await _securitiesRepo.findById(assetId);
    if (existing != null &&
        (existing.sync.ownerUserId != ownerUserId ||
            existing.sync.deletedAt != null ||
            existing.id != canonicalId ||
            existing.symbol != request.symbol.trim() ||
            existing.market != request.market.wire ||
            existing.type != request.assetType ||
            existing.currency.toUpperCase() !=
                request.assetCurrency.toUpperCase())) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.assetInvalid,
        'Existing asset identity or structural fields are incompatible.',
      );
    }
  }

  void _requireRequestIdentity(TradeEntrySubmissionRequest request) {
    if (request.transactionId.isEmpty ||
        request.accountId.isEmpty ||
        request.symbol.trim().isEmpty ||
        request.symbol.contains(':') ||
        request.assetCurrency.trim().isEmpty ||
        request.currency.trim().isEmpty ||
        request.market == AssetMarket.unknown) {
      _throwPlanMismatch(
        'Trade request identity must be canonical and nonempty.',
      );
    }
  }

  void _requirePreparedContract(PreparedTradeSubmission prepared) {
    final request = prepared.request;
    _requireRequestIdentity(request);
    final asset = prepared.assetInput;
    if (prepared.transactionId != request.transactionId ||
        prepared.frozenPrice <= Decimal.zero ||
        asset.id != Asset.idFor(request.market, request.symbol) ||
        asset.symbol != request.symbol.trim() ||
        asset.market != request.market.wire ||
        asset.type != request.assetType ||
        asset.currency != request.assetCurrency ||
        asset.name != request.assetName ||
        asset.isin != request.isin ||
        asset.sync.ownerUserId != prepared.ownerUserId ||
        asset.sync.deletedAt != null) {
      _throwPlanMismatch(
        'Prepared owner, request, asset, price, and transaction must match.',
      );
    }
  }

  void _requireExactPlan({
    required TradeEntryPlan plan,
    required TradeEntrySubmissionRequest request,
    required String assetId,
    required Decimal? expectedPrice,
    required List<Lot> openLots,
  }) {
    final tx = plan.trade;
    if (tx.id != request.transactionId ||
        tx.accountId != request.accountId ||
        tx.assetId != assetId ||
        tx.type != request.type ||
        tx.quantity != request.quantity ||
        expectedPrice != null && tx.price != expectedPrice ||
        tx.price <= Decimal.zero ||
        tx.currency != request.currency ||
        tx.tradeDate != request.tradeDate ||
        tx.settleDate != null ||
        tx.fee != request.fee ||
        tx.tax != request.tax ||
        tx.counterAccountId != null ||
        tx.note != request.note) {
      _throwPlanMismatch(
        'Planned trade must exactly match the frozen submission request.',
      );
    }

    switch (request.type) {
      case TradeType.buy:
        final lot = plan.createdLot;
        final expectedCostPerUnit =
            ((tx.quantity * tx.price + (tx.fee ?? Decimal.zero)) / tx.quantity)
                .toDecimal(scaleOnInfinitePrecision: 16);
        if (lot == null ||
            lot.id.isEmpty ||
            lot.openingTransactionId != tx.id ||
            lot.accountId != tx.accountId ||
            lot.assetId != tx.assetId ||
            lot.currency != tx.currency ||
            lot.originalQuantity != tx.quantity ||
            lot.remainingQuantity != tx.quantity ||
            lot.costPerUnit != expectedCostPerUnit ||
            lot.openedAt != tx.tradeDate ||
            plan.updatedLots.isNotEmpty ||
            plan.realizedPnL.isNotEmpty ||
            plan.unfulfilledQuantity != Decimal.zero) {
          _throwPlanMismatch(
            'Buy plan must open one exact lot and have no closing effects.',
          );
        }
        break;
      case TradeType.sell:
        _requireExactSellPlan(plan, openLots);
        break;
      case TradeType.valuationAdjust:
        if (plan.createdLot != null ||
            plan.updatedLots.isNotEmpty ||
            plan.realizedPnL.isNotEmpty ||
            plan.unfulfilledQuantity != Decimal.zero) {
          _throwPlanMismatch(
            'Valuation adjustment plan must not contain lot effects.',
          );
        }
        break;
    }
  }

  void _requireExactSellPlan(TradeEntryPlan plan, List<Lot> openLots) {
    final tx = plan.trade;
    final realized = plan.realizedPnL;
    if (plan.createdLot != null ||
        plan.unfulfilledQuantity != Decimal.zero ||
        realized.isEmpty) {
      _throwPlanMismatch(
        'Sell plan must be fully allocated to at least one open lot.',
      );
    }
    final openById = {for (final lot in openLots) lot.id: lot};
    final consumedById = <String, Decimal>{};
    var totalQuantity = Decimal.zero;
    for (final pnl in realized) {
      final lot = openById[pnl.lotId];
      if (pnl.id.isEmpty ||
          pnl.quantity <= Decimal.zero ||
          lot == null ||
          lot.isClosed ||
          pnl.sellTransactionId != tx.id ||
          pnl.accountId != tx.accountId ||
          pnl.assetId != tx.assetId ||
          pnl.currency != tx.currency ||
          pnl.realizedAt != tx.tradeDate ||
          pnl.lotOpenedAt != lot.openedAt ||
          pnl.costBasis != lot.costPerUnit * pnl.quantity ||
          pnl.proceeds != tx.price * pnl.quantity ||
          pnl.fees < Decimal.zero) {
        _throwPlanMismatch(
          'Every realized PnL row must exactly identify its consumed lot.',
        );
      }
      final consumed = (consumedById[pnl.lotId] ?? Decimal.zero) + pnl.quantity;
      if (consumed > lot.remainingQuantity) {
        _throwPlanMismatch('Sell plan consumes more than a live lot contains.');
      }
      consumedById[pnl.lotId] = consumed;
      totalQuantity += pnl.quantity;
    }
    if (totalQuantity != tx.quantity ||
        plan.updatedLots.length != consumedById.length) {
      _throwPlanMismatch(
        'Sell lot allocations and updated lots must cover the full quantity.',
      );
    }
    final updatedById = {for (final lot in plan.updatedLots) lot.id: lot};
    for (final entry in consumedById.entries) {
      final before = openById[entry.key]!;
      final after = updatedById[entry.key];
      if (after == null ||
          after.openingTransactionId != before.openingTransactionId ||
          after.accountId != before.accountId ||
          after.assetId != before.assetId ||
          after.currency != before.currency ||
          after.originalQuantity != before.originalQuantity ||
          after.remainingQuantity != before.remainingQuantity - entry.value ||
          after.costPerUnit != before.costPerUnit ||
          after.openedAt != before.openedAt) {
        _throwPlanMismatch(
          'Updated sell lots must exactly reflect realized allocations.',
        );
      }
    }
  }

  Never _throwPlanMismatch(String message) {
    throw TradeSubmissionContractError(
      TradeSubmissionContractErrorCode.identityMismatch,
      message,
    );
  }

  void _requireReceiptIdentity(
    TradeMutationReceipt receipt,
    String transactionId,
  ) {
    final price = receipt.price;
    if (receipt.transactionId != transactionId ||
        receipt.journal.after.entry.id != transactionId ||
        receipt.journal.after.postings.any(
          (posting) => posting.journalEntryId != transactionId,
        ) ||
        price != null && price.after.id != transactionId) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.identityMismatch,
        'Receipt rows must share the stable transaction id.',
      );
    }
  }

  void _requireDatabaseBindings() {
    if (!isBoundTo(_db)) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.databaseMismatch,
        'Trade repositories must share the service AppDatabase and outbox.',
      );
    }
  }

  void _requireOwner(String ownerUserId) {
    if (ownerUserId.isEmpty) {
      throw const TradeSubmissionContractError(
        TradeSubmissionContractErrorCode.ownerChanged,
        'Current owner must not be empty.',
      );
    }
  }

  Asset _assetInput(TradeEntrySubmissionRequest request, String userId) {
    const device = 'trade-preparation';
    return Asset(
      id: Asset.idFor(request.market, request.symbol),
      type: request.assetType,
      symbol: request.symbol.trim(),
      currency: request.assetCurrency,
      name: request.assetName,
      market: request.market.wire,
      isin: request.isin,
      sync: SyncMeta(
        ownerUserId: userId,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedByDevice: device,
        hlc: Hlc.zero(device),
      ),
    );
  }

  JournalEntryBuild _journalBuild(
    TradeEntrySubmissionRequest request,
    Asset asset,
    TradeEntryPlan plan,
    String uid,
  ) {
    final tx = plan.trade;

    if (request.type == TradeType.buy || request.type == TradeType.sell) {
      final cashAccountId = request.cashAccountId ?? tx.accountId;
      final feeAccountId = AccountRepository.systemAccountIdForPath(
        'expense:trading:fee',
        ownerUserId: uid,
      );
      final taxAccountId = AccountRepository.systemAccountIdForPath(
        'expense:trading:tax',
        ownerUserId: uid,
      );
      final narration = request.note?.trim().isNotEmpty == true
          ? request.note!
          : request.defaultNarration(asset);

      if (request.type == TradeType.buy) {
        return JournalEntryBuilders.buy(
          date: tx.tradeDate,
          accountId: tx.accountId,
          cashAccountId: cashAccountId,
          assetUnit: tx.assetId,
          qty: tx.quantity,
          price: tx.price,
          quoteCurrency: tx.currency,
          lotId: plan.createdLot?.id,
          acquiredOn: plan.createdLot?.openedAt,
          capitalizeFeeIntoLot: true,
          feeAmount: tx.fee,
          feeAccountId: null,
          feeCurrency: tx.fee != null ? tx.currency : null,
          taxAmount: tx.tax,
          taxAccountId: tx.tax != null ? taxAccountId : null,
          taxCurrency: tx.tax != null ? tx.currency : null,
          narration: narration,
        );
      }

      final capGainsAccountId = AccountRepository.systemAccountIdForPath(
        'income:capitalGains',
        ownerUserId: uid,
      );
      final allocations = [
        for (final pnl in plan.realizedPnL)
          SellLotAllocation(
            quantity: pnl.quantity,
            costPerUnit: (pnl.costBasis / pnl.quantity).toDecimal(
              scaleOnInfinitePrecision: 16,
            ),
            costCurrency: pnl.currency,
            lotId: pnl.lotId,
            acquiredOn: pnl.lotOpenedAt,
          ),
      ];
      return JournalEntryBuilders.sellLots(
        date: tx.tradeDate,
        accountId: tx.accountId,
        cashAccountId: cashAccountId,
        capitalGainsAccountId: capGainsAccountId,
        assetUnit: tx.assetId,
        allocations: allocations,
        price: tx.price,
        quoteCurrency: tx.currency,
        feeAmount: tx.fee,
        feeAccountId: tx.fee != null ? feeAccountId : null,
        feeCurrency: tx.fee != null ? tx.currency : null,
        taxAmount: tx.tax,
        taxAccountId: tx.tax != null ? taxAccountId : null,
        taxCurrency: tx.tax != null ? tx.currency : null,
        narration: narration,
      );
    }

    final equityAccountId = AccountRepository.systemAccountIdForPath(
      'equity:adjustments',
      ownerUserId: uid,
    );
    return JournalEntryBuilders.valuationAdjust(
      date: tx.tradeDate,
      accountId: tx.accountId,
      equityAccountId: equityAccountId,
      assetUnit: tx.assetId,
      quantity: tx.quantity,
      newValuation: tx.price,
      currency: tx.currency,
      narration: request.note,
    );
  }

  JournalEntryBuild _withEntryId(JournalEntryBuild build, String id) {
    final entry = build.entry;
    return JournalEntryBuild(
      entry: JournalEntryDraft(
        id: id,
        date: entry.date,
        settledOn: entry.settledOn,
        narration: entry.narration,
        payee: entry.payee,
        tagIds: entry.tagIds,
        flag: entry.flag,
      ),
      postings: build.postings,
    );
  }
}

/// Fully resolved input for the single local commit transaction.
final class PreparedTradeSubmission {
  const PreparedTradeSubmission({
    required this.ownerUserId,
    required this.transactionId,
    required this.request,
    required this.assetInput,
    required this.frozenPrice,
    required this.priceProvenance,
    required this.priceSource,
  });

  final String ownerUserId;
  final String transactionId;
  final TradeEntrySubmissionRequest request;
  final Asset assetInput;
  final Decimal frozenPrice;
  final PriceProvenance priceProvenance;
  final String priceSource;
}

enum TradeSubmissionContractErrorCode {
  databaseMismatch,
  ownerChanged,
  identityMismatch,
  accountInvalid,
  cashAccountInvalid,
  assetInvalid,
  lotCurrencyMismatch,
  insufficientFreshHoldings,
  backdatedSell,
  externalResolutionInTransaction,
}

final class TradeSubmissionContractError implements Exception {
  const TradeSubmissionContractError(this.code, this.message);

  final TradeSubmissionContractErrorCode code;
  final String message;

  @override
  String toString() => 'TradeSubmissionContractError(${code.name}): $message';
}

/// Versioned rows produced by one committed trade.
final class TradeMutationReceipt {
  const TradeMutationReceipt({
    required this.transactionId,
    required this.assetAfter,
    required this.journal,
    required this.price,
  });

  final String transactionId;
  final Asset assetAfter;
  final JournalMutationReceipt journal;
  final PriceMutationReceipt? price;

  String get assetId => assetAfter.id;
}

class TradeEntrySubmissionRequest {
  const TradeEntrySubmissionRequest({
    required this.transactionId,
    required this.symbol,
    required this.market,
    required this.assetType,
    required this.assetCurrency,
    required this.type,
    required this.accountId,
    required this.quantity,
    required this.currency,
    required this.tradeDate,
    required this.defaultNarration,
    this.assetName,
    this.isin,
    this.cashAccountId,
    this.price,
    this.fee,
    this.tax,
    this.note,
  });

  final String transactionId;
  final String symbol;
  final AssetMarket market;
  final AssetType assetType;
  final String assetCurrency;
  final String? assetName;
  final String? isin;

  final TradeType type;
  final String accountId;
  final String? cashAccountId;
  final Decimal quantity;
  final Decimal? price;
  final String currency;
  final DateTime tradeDate;
  final Decimal? fee;
  final Decimal? tax;
  final String? note;
  final String Function(Asset asset) defaultNarration;
}
