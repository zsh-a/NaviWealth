import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
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
    required SecuritiesAssetRepository securitiesRepo,
    required TradeEntryService tradeService,
    required JournalEntryRepository journalEntryRepo,
    required PriceRepository priceRepo,
    required Future<String> Function() currentUserId,
  }) : _securitiesRepo = securitiesRepo,
       _tradeService = tradeService,
       _journalEntryRepo = journalEntryRepo,
       _priceRepo = priceRepo,
       _currentUserId = currentUserId;

  final SecuritiesAssetRepository _securitiesRepo;
  final TradeEntryService _tradeService;
  final JournalEntryRepository _journalEntryRepo;
  final PriceRepository _priceRepo;
  final Future<String> Function() _currentUserId;

  Future<Decimal> balanceByAccountUnit(String accountId, String unit) {
    return _journalEntryRepo.balanceByAccountUnit(accountId, unit);
  }

  Future<void> submit(TradeEntrySubmissionRequest request) async {
    final asset = await _securitiesRepo.upsertSecurity(
      symbol: request.symbol,
      market: request.market,
      type: request.assetType,
      currency: request.assetCurrency,
      name: request.assetName,
      isin: request.isin,
    );
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
    final tx = plan.trade;
    final uid = await _currentUserId();

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
        final build = JournalEntryBuilders.buy(
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
        await _journalEntryRepo.create(
          entry: build.entry,
          postings: build.postings,
        );
        await _recordTradePrice(
          tx.assetId,
          request.currency,
          tx.tradeDate,
          tx.price,
        );
        return;
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
      final build = JournalEntryBuilders.sell(
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
      await _journalEntryRepo.create(
        entry: build.entry,
        postings: build.postings,
      );
      await _recordTradePrice(
        tx.assetId,
        request.currency,
        tx.tradeDate,
        tx.price,
      );
      return;
    }

    final equityAccountId = AccountRepository.systemAccountIdForPath(
      'equity:adjustments',
      ownerUserId: uid,
    );
    final build = JournalEntryBuilders.valuationAdjust(
      date: tx.tradeDate,
      accountId: request.accountId,
      equityAccountId: equityAccountId,
      assetUnit: tx.assetId,
      quantity: tx.quantity,
      newValuation: tx.price,
      currency: request.currency,
      narration: request.note,
    );
    await _journalEntryRepo.create(
      entry: build.entry,
      postings: build.postings,
    );
    await _priceRepo.record(
      unit: tx.assetId,
      quoteCurrency: request.currency,
      observedOn: tx.tradeDate,
      perUnit: tx.price,
      source: 'manual',
    );
  }

  Future<void> _recordTradePrice(
    String assetId,
    String currency,
    DateTime observedOn,
    Decimal price,
  ) {
    return _priceRepo.record(
      unit: assetId,
      quoteCurrency: currency,
      observedOn: observedOn,
      perUnit: price,
      source: 'trade',
    );
  }
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
