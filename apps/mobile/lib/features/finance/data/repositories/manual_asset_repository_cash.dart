part of 'manual_asset_repository.dart';

Future<Decimal?> _manualCashBalanceFromPostings(
  ManualAssetRepository repo,
  String assetId,
) async {
  final assetRow = await (repo._db.select(
    repo._db.assets,
  )..where((t) => t.id.equals(assetId))).getSingleOrNull();
  if (assetRow == null) return null;
  final meta = ManualAssetMetadata.decode(assetRow.metadataJson);
  if (meta == null) return null;
  final jeRepo = repo._journalEntryRepo;
  if (jeRepo != null) {
    return jeRepo.balanceByAccountUnit(meta.accountId, assetRow.currency);
  }
  final rows =
      await (repo._db.select(repo._db.postings).join([
              innerJoin(
                repo._db.journalEntries,
                repo._db.journalEntries.id.equalsExp(
                  repo._db.postings.journalEntryId,
                ),
              ),
            ])
            ..where(repo._db.postings.accountId.equals(meta.accountId))
            ..where(repo._db.postings.unit.equals(assetRow.currency))
            ..where(repo._db.postings.deletedAt.isNull())
            ..where(repo._db.journalEntries.deletedAt.isNull()))
          .get();
  if (rows.isEmpty) return null;
  var sum = Decimal.zero;
  for (final row in rows) {
    sum += row.readTable(repo._db.postings).units;
  }
  return sum;
}

Future<Asset?> _findManualCashByAccountId(
  ManualAssetRepository repo,
  String accountId,
) async {
  final rows =
      await (repo._db.select(repo._db.assets)
            ..where((t) => t.type.equalsValue(AssetType.cash))
            ..where((t) => t.deletedAt.isNull()))
          .get();
  for (final row in rows) {
    final meta = ManualAssetMetadata.decode(row.metadataJson);
    if (meta is CashMetadata && meta.accountId == accountId) {
      return repo._toAsset(row);
    }
  }
  return null;
}

Future<Asset> _createManualCash(
  ManualAssetRepository repo, {
  required String accountId,
  required String currency,
  required Decimal balance,
  String? nickname,
}) {
  if (balance < Decimal.zero) {
    throw ArgumentError.value(balance, 'balance', 'must be >= 0');
  }
  final metadata = CashMetadata(accountId: accountId);
  return _createManualAsset(
    repo,
    type: AssetType.cash,
    symbol: currency,
    currency: currency,
    name: nickname ?? '$currency cash',
    metadata: metadata,
    accountId: accountId,
    initialValuation: balance,
  );
}

Future<int> _repairManualCashBalancePostings(ManualAssetRepository repo) async {
  final jeRepo = repo._journalEntryRepo;
  if (jeRepo == null) return 0;
  final rows =
      await (repo._db.select(repo._db.assets)
            ..where((t) => t.type.equalsValue(AssetType.cash))
            ..where((t) => t.deletedAt.isNull()))
          .get();
  var repaired = 0;
  for (final row in rows) {
    final meta = ManualAssetMetadata.decode(row.metadataJson);
    if (meta is! CashMetadata) continue;
    final valuation = await repo.latestValuation(row.id);
    if (valuation == null) continue;
    if (valuation == Decimal.zero) continue;
    final hasTaggedLedger = await _hasManualAssetTaggedPosting(
      repo,
      assetId: row.id,
      accountId: meta.accountId,
      currency: row.currency,
    );
    if (hasTaggedLedger) continue;
    await _recordManualCashBalanceDelta(
      repo,
      assetId: row.id,
      accountId: meta.accountId,
      currency: row.currency,
      delta: valuation,
      observedOn: DateTime.now().toUtc(),
      ownerUserId: row.ownerUserId,
      narration: 'Repair cash balance',
    );
    repaired++;
  }
  return repaired;
}

Future<bool> _hasManualAssetTaggedPosting(
  ManualAssetRepository repo, {
  required String assetId,
  required String accountId,
  required String currency,
}) async {
  final rows =
      await (repo._db.select(repo._db.postings).join([
              innerJoin(
                repo._db.journalEntries,
                repo._db.journalEntries.id.equalsExp(
                  repo._db.postings.journalEntryId,
                ),
              ),
            ])
            ..where(repo._db.postings.accountId.equals(accountId))
            ..where(repo._db.postings.unit.equals(currency))
            ..where(repo._db.postings.deletedAt.isNull())
            ..where(repo._db.journalEntries.deletedAt.isNull()))
          .get();
  final tag = 'asset:$assetId';
  for (final row in rows) {
    final entry = row.readTable(repo._db.journalEntries);
    final tags = (jsonDecode(entry.tagIdsJson) as List<dynamic>).cast<String>();
    if (tags.contains(tag)) return true;
  }
  return false;
}

Future<void> _recordManualCashBalanceDelta(
  ManualAssetRepository repo, {
  required String assetId,
  required String accountId,
  required String currency,
  required Decimal delta,
  required DateTime observedOn,
  required String ownerUserId,
  String? narration,
}) async {
  if (delta == Decimal.zero) return;
  final jeRepo = repo._journalEntryRepo;
  if (jeRepo == null) return;
  final build = JournalEntryBuilders.openingBalance(
    date: observedOn,
    accountId: accountId,
    openingBalanceAccountId: AccountRepository.systemAccountIdForPath(
      'equity:openingBalance',
      ownerUserId: ownerUserId,
    ),
    amount: delta,
    currency: currency,
    narration: narration,
    tagIds: ['asset:$assetId'],
  );
  await jeRepo.create(entry: build.entry, postings: build.postings);
}
