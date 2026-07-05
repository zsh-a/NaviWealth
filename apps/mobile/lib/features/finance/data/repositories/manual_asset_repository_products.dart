part of 'manual_asset_repository.dart';

Future<Asset> _createManualDeposit(
  ManualAssetRepository repo, {
  required String accountId,
  required AssetType type,
  required String name,
  required String currency,
  required Decimal principal,
  required Decimal interestRate,
  DateTime? startDate,
  DateTime? maturityDate,
  bool autoRenew = false,
  Decimal? currentValuation,
}) {
  assert(
    type == AssetType.bankDepositTerm || type == AssetType.bankDepositDemand,
    'createDeposit only accepts bankDepositTerm / bankDepositDemand',
  );
  final metadata = DepositMetadata(
    accountId: accountId,
    principal: principal,
    interestRate: interestRate,
    startDate: startDate,
    maturityDate: maturityDate,
    autoRenew: autoRenew,
  );
  return _createManualAsset(
    repo,
    type: type,
    symbol: name,
    currency: currency,
    name: name,
    metadata: metadata,
    accountId: accountId,
    initialValuation: currentValuation ?? principal,
  );
}

Future<Asset> _createManualWealthProduct(
  ManualAssetRepository repo, {
  required String accountId,
  required String name,
  required String currency,
  required Decimal principal,
  required Decimal expectedAnnualReturn,
  DateTime? startDate,
  DateTime? maturityDate,
  String? issuer,
  String? productCode,
  Decimal? currentValuation,
}) {
  final metadata = WealthProductMetadata(
    accountId: accountId,
    principal: principal,
    expectedAnnualReturn: expectedAnnualReturn,
    startDate: startDate,
    maturityDate: maturityDate,
    issuer: issuer,
    productCode: productCode,
  );
  return _createManualAsset(
    repo,
    type: AssetType.wealthProduct,
    symbol: productCode ?? name,
    currency: currency,
    name: name,
    metadata: metadata,
    accountId: accountId,
    initialValuation: currentValuation ?? principal,
  );
}

Future<Asset> _createManualAsset(
  ManualAssetRepository repo, {
  required AssetType type,
  required String symbol,
  required String currency,
  required String name,
  required ManualAssetMetadata metadata,
  required String accountId,
  required Decimal initialValuation,
}) async {
  final stamp = await repo._stamper.stamp();
  final id = repo._uuid.v4();
  final encoded = metadata.encode();
  final companion = AssetsCompanion.insert(
    id: id,
    type: type,
    symbol: symbol,
    currency: currency,
    name: Value(name),
    metadataJson: Value(encoded),
    ownerUserId: stamp.ownerUserId,
    updatedAt: stamp.now,
    updatedByDevice: stamp.deviceId,
    hlc: stamp.hlc,
  );
  final fields = <String, Object?>{
    'id': id,
    'type': type.name,
    'symbol': symbol,
    'currency': currency,
    'name': name,
    'metadata_json': encoded,
    'owner_user_id': stamp.ownerUserId,
    'updated_at': stamp.now.toUtc().toIso8601String(),
    'updated_by_device': stamp.deviceId,
    'hlc': stamp.hlc.toString(),
  };
  await repo._db.transaction(() async {
    await repo._db.into(repo._db.assets).insert(companion);
    await repo._outbox.enqueue(
      table: ManualAssetRepository._tableName,
      rowId: id,
    );
    await repo._eventLog.recordCreated(
      entityTable: ManualAssetRepository._tableName,
      entityId: id,
      stamp: stamp,
      after: fields,
    );
    if (initialValuation > Decimal.zero ||
        (type == AssetType.cash && initialValuation == Decimal.zero)) {
      await _recordManualValuation(
        repo,
        assetId: id,
        accountId: accountId,
        currency: currency,
        value: initialValuation,
        observedOn: stamp.now,
        ownerUserId: stamp.ownerUserId,
        type: type,
        previousValue: Decimal.zero,
      );
    }
  });
  return (await repo.findById(id))!;
}
