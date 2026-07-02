import 'package:decimal/decimal.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';

import '../domain/options_strategy_profile.dart';
import '../domain/trade_journal_entry.dart';

/// Mirrors an Income Planner journal row into the forward ledger.
///
/// The options journal remains the strategy/review source of truth. This
/// service creates deterministic ledger entries beside it so option premium,
/// close debit, assignment buys, and called-away sells affect the existing
/// cash/holdings/dashboard read models.
class OptionsJournalLedgerService {
  OptionsJournalLedgerService({
    required JournalEntryRepository journalEntryRepo,
    required ManualAssetRepository manualAssetRepo,
    required SecuritiesAssetRepository securitiesAssetRepo,
    required PriceRepository priceRepo,
    required Future<HoldingService> Function() holdingService,
    required Future<String> Function() currentUserId,
  }) : _journalEntryRepo = journalEntryRepo,
       _manualAssetRepo = manualAssetRepo,
       _securitiesAssetRepo = securitiesAssetRepo,
       _priceRepo = priceRepo,
       _holdingService = holdingService,
       _currentUserId = currentUserId;

  final JournalEntryRepository _journalEntryRepo;
  final ManualAssetRepository _manualAssetRepo;
  final SecuritiesAssetRepository _securitiesAssetRepo;
  final PriceRepository _priceRepo;
  final Future<HoldingService> Function() _holdingService;
  final Future<String> Function() _currentUserId;

  static const int defaultContractSize = 100;

  Future<void> mirror(TradeJournalEntry entry) async {
    final cashAccountId = entry.cashAccountId ?? entry.brokerageAccountId;
    if (cashAccountId == null || cashAccountId.isEmpty) {
      await removeMirrors(entry.id);
      return;
    }

    await _ensureCashAsset(accountId: cashAccountId, currency: entry.currency);
    await _upsertPremium(entry, cashAccountId: cashAccountId);
    await _upsertCloseDebit(entry, cashAccountId: cashAccountId);
    await _upsertAssignment(entry, cashAccountId: cashAccountId);
  }

  Future<void> removeMirrors(String entryId) async {
    for (final leg in _OptionsLedgerLeg.values) {
      await _deleteIfPresent(_ledgerEntryId(entryId, leg));
    }
  }

  Future<void> _upsertPremium(
    TradeJournalEntry entry, {
    required String cashAccountId,
  }) async {
    final amount = entry.entryCredit;
    if (amount <= Decimal.zero) {
      await _deleteIfPresent(
        _ledgerEntryId(entry.id, _OptionsLedgerLeg.premium),
      );
      return;
    }
    final uid = await _currentUserId();
    final build = _cashIncomeBuild(
      id: _ledgerEntryId(entry.id, _OptionsLedgerLeg.premium),
      date: entry.openedAt,
      cashAccountId: cashAccountId,
      incomeAccountId: AccountRepository.systemAccountIdForPath(
        'income:options',
        ownerUserId: uid,
      ),
      amount: amount,
      currency: entry.currency,
      narration: 'Options premium ${entry.optionSymbol}',
      tagIds: _tags(entry),
    );
    await _upsertBuild(build);
  }

  Future<void> _upsertCloseDebit(
    TradeJournalEntry entry, {
    required String cashAccountId,
  }) async {
    final id = _ledgerEntryId(entry.id, _OptionsLedgerLeg.closeDebit);
    final debit = entry.exitDebit;
    if (entry.status == TradeJournalStatus.open ||
        debit == null ||
        debit <= Decimal.zero) {
      await _deleteIfPresent(id);
      return;
    }
    final uid = await _currentUserId();
    final build = JournalEntryBuild(
      entry: JournalEntryDraft(
        id: id,
        date: entry.closedAt ?? DateTime.now().toUtc(),
        narration: 'Options close debit ${entry.optionSymbol}',
        tagIds: _tags(entry),
      ),
      postings: <PostingDraft>[
        PostingDraft(
          position: 0,
          accountId: AccountRepository.systemAccountIdForPath(
            'income:options',
            ownerUserId: uid,
          ),
          units: debit,
          unit: entry.currency,
        ),
        PostingDraft(
          position: 1,
          accountId: cashAccountId,
          units: -debit,
          unit: entry.currency,
        ),
      ],
    );
    await _upsertBuild(build);
  }

  Future<void> _upsertAssignment(
    TradeJournalEntry entry, {
    required String cashAccountId,
  }) async {
    final id = _ledgerEntryId(entry.id, _OptionsLedgerLeg.assignment);
    if (entry.status != TradeJournalStatus.assigned) {
      await _deleteIfPresent(id);
      return;
    }
    final brokerageAccountId = entry.brokerageAccountId;
    final strike = entry.strikePrice;
    if (brokerageAccountId == null ||
        brokerageAccountId.isEmpty ||
        strike == null ||
        strike <= Decimal.zero) {
      await _deleteIfPresent(id);
      return;
    }

    final asset = await _ensureUnderlyingAsset(entry);
    final qty = Decimal.fromInt(entry.contractSize ?? defaultContractSize);
    final date = entry.closedAt ?? DateTime.now().toUtc();
    final JournalEntryBuild build;
    switch (entry.strategy) {
      case OptionsStrategyKind.cashSecuredPut:
        build = JournalEntryBuilders.buy(
          date: date,
          accountId: brokerageAccountId,
          cashAccountId: cashAccountId,
          assetUnit: asset.id,
          qty: qty,
          price: strike,
          quoteCurrency: entry.currency,
          lotId: 'options:${entry.id}:assignment',
          acquiredOn: date,
          narration: 'Put assigned ${entry.symbol}',
          tagIds: _tags(entry),
        );
      case OptionsStrategyKind.coveredCall:
        final basis = await _costBasisForCalledAway(
          accountId: brokerageAccountId,
          assetId: asset.id,
          quantity: qty,
          fallbackPrice: strike,
          currency: entry.currency,
          asOf: date,
        );
        build = JournalEntryBuilders.sell(
          date: date,
          accountId: brokerageAccountId,
          cashAccountId: cashAccountId,
          capitalGainsAccountId: AccountRepository.systemAccountIdForPath(
            'income:capitalGains',
            ownerUserId: await _currentUserId(),
          ),
          assetUnit: asset.id,
          qty: qty,
          price: strike,
          quoteCurrency: entry.currency,
          costPerUnit: basis.costPerUnit,
          costCurrency: basis.currency,
          lotId: basis.lotId,
          acquiredOn: basis.acquiredOn,
          narration: 'Covered call assigned ${entry.symbol}',
          tagIds: _tags(entry),
        );
    }

    final forced = JournalEntryBuild(
      entry: JournalEntryDraft(
        id: id,
        date: build.entry.date,
        settledOn: build.entry.settledOn,
        narration: build.entry.narration,
        payee: build.entry.payee,
        tagIds: build.entry.tagIds,
        flag: build.entry.flag,
      ),
      postings: build.postings,
    );
    await _upsertBuild(forced);
    await _priceRepo.record(
      unit: asset.id,
      quoteCurrency: entry.currency,
      observedOn: date,
      perUnit: strike,
      source: 'options_assignment',
    );
  }

  Future<Asset> _ensureUnderlyingAsset(TradeJournalEntry entry) async {
    final market =
        assetMarketFromWire(entry.underlyingMarket) ??
        inferAssetMarket(entry.symbol);
    final effectiveMarket = market == AssetMarket.unknown
        ? AssetMarket.usStock
        : market;
    final existing = await _securitiesAssetRepo.findBySymbolAndMarket(
      entry.symbol,
      effectiveMarket,
    );
    if (existing != null) return existing;
    return _securitiesAssetRepo.upsertSecurity(
      symbol: entry.symbol,
      market: effectiveMarket,
      type: AssetType.stock,
      currency: entry.currency,
      name: entry.symbol,
    );
  }

  Future<void> _ensureCashAsset({
    required String accountId,
    required String currency,
  }) async {
    final existing = await _manualAssetRepo.findCashByAccountId(accountId);
    if (existing != null) return;
    await _manualAssetRepo.createCash(
      accountId: accountId,
      currency: currency,
      balance: Decimal.zero,
      nickname: '$currency options cash',
    );
  }

  Future<_CostBasis> _costBasisForCalledAway({
    required String accountId,
    required String assetId,
    required Decimal quantity,
    required Decimal fallbackPrice,
    required String currency,
    required DateTime asOf,
  }) async {
    final holdingService = await _holdingService();
    final lots = await holdingService.lotsAt(
      asOf.subtract(const Duration(microseconds: 1)),
    );
    final candidates =
        lots
            .where(
              (lot) =>
                  !lot.isClosed &&
                  lot.accountId == accountId &&
                  lot.assetId == assetId &&
                  lot.currency == currency,
            )
            .toList()
          ..sort((a, b) => a.openedAt.compareTo(b.openedAt));
    if (candidates.isEmpty) {
      return _CostBasis(costPerUnit: fallbackPrice, currency: currency);
    }

    var remaining = quantity;
    var cost = Decimal.zero;
    Lot? first;
    for (final lot in candidates) {
      if (remaining <= Decimal.zero) break;
      first ??= lot;
      final take = lot.remainingQuantity < remaining
          ? lot.remainingQuantity
          : remaining;
      cost += take * lot.costPerUnit;
      remaining -= take;
    }
    if (remaining > Decimal.zero || cost == Decimal.zero) {
      return _CostBasis(costPerUnit: fallbackPrice, currency: currency);
    }
    final costPerUnit = (cost / quantity).toDecimal(
      scaleOnInfinitePrecision: 16,
    );
    return _CostBasis(
      costPerUnit: costPerUnit,
      currency: currency,
      lotId: first?.id,
      acquiredOn: first?.openedAt,
    );
  }

  JournalEntryBuild _cashIncomeBuild({
    required String id,
    required DateTime date,
    required String cashAccountId,
    required String incomeAccountId,
    required Decimal amount,
    required String currency,
    required String narration,
    required List<String> tagIds,
  }) {
    return JournalEntryBuild(
      entry: JournalEntryDraft(
        id: id,
        date: date,
        narration: narration,
        tagIds: tagIds,
      ),
      postings: <PostingDraft>[
        PostingDraft(
          position: 0,
          accountId: cashAccountId,
          units: amount,
          unit: currency,
        ),
        PostingDraft(
          position: 1,
          accountId: incomeAccountId,
          units: -amount,
          unit: currency,
        ),
      ],
    );
  }

  Future<void> _upsertBuild(JournalEntryBuild build) async {
    final id = build.entry.id;
    if (id == null) {
      throw StateError('options ledger mirror requires deterministic JE id');
    }
    final existing = await _journalEntryRepo.getById(id);
    if (existing == null) {
      await _journalEntryRepo.create(
        entry: build.entry,
        postings: build.postings,
      );
      return;
    }
    await _journalEntryRepo.replacePostings(
      id: id,
      entry: build.entry,
      postings: build.postings,
    );
  }

  Future<void> _deleteIfPresent(String id) async {
    final existing = await _journalEntryRepo.getById(id);
    if (existing == null) return;
    await _journalEntryRepo.softDelete(id);
  }

  List<String> _tags(TradeJournalEntry entry) => <String>[
    'options:${entry.id}',
    'option:${entry.optionSymbol}',
  ];

  String _ledgerEntryId(String entryId, _OptionsLedgerLeg leg) =>
      'options:$entryId:${leg.name}';
}

enum _OptionsLedgerLeg { premium, closeDebit, assignment }

class _CostBasis {
  const _CostBasis({
    required this.costPerUnit,
    required this.currency,
    this.lotId,
    this.acquiredOn,
  });

  final Decimal costPerUnit;
  final String currency;
  final String? lotId;
  final DateTime? acquiredOn;
}
