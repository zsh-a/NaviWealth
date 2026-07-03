import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import '../domain/options_strategy_profile.dart';
import '../domain/trade_journal_entry.dart';

part 'options_journal_ledger_assets.dart';
part 'options_journal_ledger_builds.dart';
part 'options_journal_ledger_models.dart';

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

    await _ensureOptionsCashAsset(
      manualAssetRepo: _manualAssetRepo,
      accountId: cashAccountId,
      currency: entry.currency,
    );
    await _upsertOptionsPremium(
      journalEntryRepo: _journalEntryRepo,
      currentUserId: _currentUserId,
      entry: entry,
      cashAccountId: cashAccountId,
    );
    await _upsertOptionsCloseDebit(
      journalEntryRepo: _journalEntryRepo,
      currentUserId: _currentUserId,
      entry: entry,
      cashAccountId: cashAccountId,
    );
    await _upsertOptionsAssignment(
      journalEntryRepo: _journalEntryRepo,
      securitiesAssetRepo: _securitiesAssetRepo,
      priceRepo: _priceRepo,
      holdingService: _holdingService,
      currentUserId: _currentUserId,
      entry: entry,
      cashAccountId: cashAccountId,
      defaultContractSize: defaultContractSize,
    );
  }

  Future<void> removeMirrors(String entryId) async {
    await _removeOptionsLedgerMirrors(
      journalEntryRepo: _journalEntryRepo,
      entryId: entryId,
    );
  }
}
