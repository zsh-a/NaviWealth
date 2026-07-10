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

/// Persists a planned trade into ledger entries and price observations.
///
/// [TradeEntryService] stays pure and returns a [TradeEntryPlan]. This
/// application service owns the impure write-through into assets,
/// journal_entries/postings, and prices so UI surfaces don't duplicate
/// ledger construction details.
class TradeEntrySubmissionService {
  const TradeEntrySubmissionService({
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
       _currentUserId = currentUserId;

  final AppDatabase _db;
  final SecuritiesAssetRepository _securitiesRepo;
  final TradeEntryService _tradeService;
  final JournalEntryRepository _journalEntryRepo;
  final PriceRepository _priceRepo;
  final Future<String> Function() _currentUserId;

  Future<Decimal> balanceByAccountUnit(String accountId, String unit) {
    return _journalEntryRepo.balanceByAccountUnit(accountId, unit);
  }

  /// Resolves every external/domain dependency without opening a DB write.
  Future<PreparedTradeSubmission> prepare(
    TradeEntrySubmissionRequest request,
  ) async {
    final uid = await _currentUserId();
    final asset = _assetInput(request, uid);
    final draft = TradeDraft(
      type: request.type,
      asset: asset,
      accountId: request.accountId,
      quantity: request.quantity,
      price: request.price,
      currency: request.currency,
      tradeDate: request.tradeDate,
      fee: request.fee,
      tax: request.tax,
      note: request.note,
    );
    final plan = await _tradeService.buildPlan(draft, openLots: <Lot>[]);
    final journal = _journalBuild(request, asset, plan, uid);
    return PreparedTradeSubmission(
      request: request,
      assetInput: asset,
      plan: plan,
      journal: _withEntryId(journal, plan.trade.id),
      priceSource: request.type == TradeType.valuationAdjust
          ? 'manual'
          : 'trade',
    );
  }

  /// Commits security metadata, ledger rows, price, and outbox atomically.
  Future<TradeMutationReceipt> commit(PreparedTradeSubmission prepared) async {
    return _db.transaction(() async {
      final request = prepared.request;
      final assetAfter = await _securitiesRepo.upsertSecurity(
        symbol: prepared.assetInput.symbol,
        market: request.market,
        type: request.assetType,
        currency: request.assetCurrency,
        name: request.assetName,
        isin: request.isin,
      );
      final journalReceipt = await _journalEntryRepo.createWithReceipt(
        entry: prepared.journal.entry,
        postings: prepared.journal.postings,
      );
      final tx = prepared.plan.trade;
      final priceReceipt = await _priceRepo.upsertWithReceipt(
        id: tx.id,
        unit: tx.assetId,
        quoteCurrency: request.currency,
        observedOn: tx.tradeDate,
        perUnit: tx.price,
        source: prepared.priceSource,
      );
      return TradeMutationReceipt(
        transactionId: tx.id,
        assetAfter: assetAfter,
        journal: journalReceipt,
        price: priceReceipt,
      );
    });
  }

  Future<TradeMutationReceipt> submit(
    TradeEntrySubmissionRequest request,
  ) async {
    final prepared = await prepare(request);
    return commit(prepared);
  }

  /// Reverses price + journal atomically while preserving security metadata.
  Future<void> undoMutation(TradeMutationReceipt receipt) async {
    await _db.transaction(() async {
      // Every conflict check must complete before either repository writes.
      await _journalEntryRepo.validateUndo(receipt.journal);
      final price = receipt.price;
      if (price != null) await _priceRepo.validateUndo(price);

      if (price != null) await _priceRepo.undoMutation(price);
      await _journalEntryRepo.undoMutation(receipt.journal);
    });
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
      final cashAccountId = request.cashAccountId ?? request.accountId;
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
          accountId: request.accountId,
          cashAccountId: cashAccountId,
          assetUnit: tx.assetId,
          qty: tx.quantity,
          price: tx.price,
          quoteCurrency: request.currency,
          lotId: plan.createdLot?.id,
          acquiredOn: plan.createdLot?.openedAt,
          feeAmount: tx.fee,
          feeAccountId: tx.fee != null ? feeAccountId : null,
          feeCurrency: tx.fee != null ? request.currency : null,
          taxAmount: tx.tax,
          taxAccountId: tx.tax != null ? taxAccountId : null,
          taxCurrency: tx.tax != null ? request.currency : null,
          narration: narration,
        );
      }

      final capGainsAccountId = AccountRepository.systemAccountIdForPath(
        'income:capitalGains',
        ownerUserId: uid,
      );
      final pnl = plan.realizedPnL;
      Decimal costPerUnit;
      String costCurrency;
      String? sellLotId;
      DateTime? sellAcquiredOn;
      if (pnl.isNotEmpty) {
        final first = pnl.first;
        costPerUnit = first.quantity.sign != 0
            ? (first.costBasis / first.quantity).toDecimal(
                scaleOnInfinitePrecision: 16,
              )
            : tx.price;
        costCurrency = first.currency;
        sellLotId = first.lotId;
        sellAcquiredOn = first.lotOpenedAt;
      } else {
        costPerUnit = tx.price;
        costCurrency = request.currency;
      }
      return JournalEntryBuilders.sell(
        date: tx.tradeDate,
        accountId: request.accountId,
        cashAccountId: cashAccountId,
        capitalGainsAccountId: capGainsAccountId,
        assetUnit: tx.assetId,
        qty: tx.quantity,
        price: tx.price,
        quoteCurrency: request.currency,
        costPerUnit: costPerUnit,
        costCurrency: costCurrency,
        lotId: sellLotId,
        acquiredOn: sellAcquiredOn,
        feeAmount: tx.fee,
        feeAccountId: tx.fee != null ? feeAccountId : null,
        feeCurrency: tx.fee != null ? request.currency : null,
        taxAmount: tx.tax,
        taxAccountId: tx.tax != null ? taxAccountId : null,
        taxCurrency: tx.tax != null ? request.currency : null,
        narration: narration,
      );
    }

    final equityAccountId = AccountRepository.systemAccountIdForPath(
      'equity:adjustments',
      ownerUserId: uid,
    );
    return JournalEntryBuilders.valuationAdjust(
      date: tx.tradeDate,
      accountId: request.accountId,
      equityAccountId: equityAccountId,
      assetUnit: tx.assetId,
      quantity: tx.quantity,
      newValuation: tx.price,
      currency: request.currency,
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
    required this.request,
    required this.assetInput,
    required this.plan,
    required this.journal,
    required this.priceSource,
  });

  final TradeEntrySubmissionRequest request;
  final Asset assetInput;
  final TradeEntryPlan plan;
  final JournalEntryBuild journal;
  final String priceSource;
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
