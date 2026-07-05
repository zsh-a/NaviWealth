part of 'manual_asset_repository.dart';

Future<Decimal?> _latestManualAssetValuation(
  ManualAssetRepository repo,
  String assetId, {
  DateTime? asOf,
}) async {
  final row = await (repo._db.select(
    repo._db.assets,
  )..where((t) => t.id.equals(assetId))).getSingleOrNull();
  if (row == null) return null;
  final observed = await repo._priceRepo.latestAt(
    unit: assetId,
    quoteCurrency: row.currency,
    asOf: asOf ?? DateTime.now().toUtc(),
  );
  return observed?.perUnit;
}

Future<Asset> _recordManualValuationAdjust(
  ManualAssetRepository repo, {
  required String assetId,
  required Decimal newValuation,
  DateTime? asOf,
  String? reason,
}) async {
  final row = await (repo._db.select(
    repo._db.assets,
  )..where((t) => t.id.equals(assetId))).getSingleOrNull();
  if (row == null) {
    throw StateError('Asset $assetId does not exist');
  }
  final observedOn = asOf ?? DateTime.now().toUtc();
  final previous = await repo._priceRepo.latestAt(
    unit: assetId,
    quoteCurrency: row.currency,
    asOf: observedOn,
  );
  await _recordManualValuation(
    repo,
    assetId: assetId,
    accountId: _accountIdForManualAsset(row),
    currency: row.currency,
    value: newValuation,
    observedOn: observedOn,
    narration: reason,
    ownerUserId: row.ownerUserId,
    type: row.type,
    previousValue: previous?.perUnit,
  );
  await repo._eventLog.recordFieldChanged(
    entityTable: ManualAssetRepository._tableName,
    entityId: assetId,
    stamp: await repo._stamper.stamp(),
    before: <String, Object?>{
      'valuation': previous?.perUnit.toString(),
      'observed_on': previous?.observedOn.toUtc().toIso8601String(),
    },
    after: <String, Object?>{
      'valuation': newValuation.toString(),
      'observed_on': observedOn.toUtc().toIso8601String(),
    },
    reason: reason,
  );
  return (await repo.findById(assetId))!;
}

Future<void> _recordManualValuation(
  ManualAssetRepository repo, {
  required String assetId,
  required String accountId,
  required String currency,
  required Decimal value,
  required DateTime observedOn,
  required String ownerUserId,
  required AssetType type,
  Decimal? previousValue,
  String? narration,
}) async {
  await repo._priceRepo.record(
    unit: assetId,
    quoteCurrency: currency,
    observedOn: observedOn,
    perUnit: value,
    source: 'manual',
    allowZero: type == AssetType.cash,
  );
  final jeRepo = repo._journalEntryRepo;
  if (jeRepo == null) return;
  final JournalEntryBuild build;
  if (type == AssetType.cash) {
    final delta = value - (previousValue ?? Decimal.zero);
    await _recordManualCashBalanceDelta(
      repo,
      assetId: assetId,
      accountId: accountId,
      currency: currency,
      delta: delta,
      observedOn: observedOn,
      ownerUserId: ownerUserId,
      narration: narration ?? 'Cash balance',
    );
    return;
  } else {
    final equityAccountId = AccountRepository.systemAccountIdForPath(
      'equity:adjustments',
      ownerUserId: ownerUserId,
    );
    build = JournalEntryBuilders.valuationAdjust(
      date: observedOn,
      accountId: accountId,
      equityAccountId: equityAccountId,
      assetUnit: assetId,
      quantity: Decimal.zero,
      newValuation: value,
      currency: currency,
      narration: narration,
    );
  }
  await jeRepo.create(entry: build.entry, postings: build.postings);
}

String _accountIdForManualAsset(AssetRow row) {
  final meta = ManualAssetMetadata.decode(row.metadataJson);
  return meta?.accountId ?? row.id;
}
