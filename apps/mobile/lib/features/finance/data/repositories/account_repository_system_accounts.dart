part of 'account_repository.dart';

extension AccountRepositorySystemAccounts on AccountRepository {
  /// Idempotently seeds the default Beancount-style account tree the
  /// double-entry posting model leans on:
  ///
  /// ```
  /// Income/{Salary,Dividend,Interest,CapitalGains,Other}
  /// Expenses/{Dining,Groceries,Coffee,Transport,RideHailing,Housing,Utilities,
  /// Household,Shopping,Subscriptions,Entertainment,Medical,Fitness,Education,
  /// Travel,Communication,FamilySupport,Gift,Pets,Trading/{Fee,Tax,Interest},
  /// Tax/{Withholding},Other}
  /// Equity/{OpeningBalance,Splits,Adjustments}
  /// ```
  ///
  /// Three roots (carrying the existing ids) plus a curated set of
  /// common leaves for a total of 38 seeded accounts on a fresh install.
  ///
  /// Each row uses a deterministic id derived from
  /// [AccountRepository.systemAccountIdForPath], so re-running the seed is a
  /// free no-op and a sync-borne replay never duplicates a row. Returns the
  /// number of rows actually inserted on this call (0 on a re-seed). The seed
  /// list is iterated in parent-before-child order; the seeder still resolves
  /// a missing parent gracefully because the parent / child relationship has
  /// no SQL FK.
  ///
  /// [currency] picks the carrier currency for the seeded rows. The dashboard
  /// converts everything through FX, so the currency choice is largely cosmetic
  /// -- defaulting to `CNY` matches the app's primary locale and keeps system
  /// rows out of the FX-mismatch banner on fresh installs that haven't yet
  /// pulled an FX rate table.
  Future<int> seedSystemAccounts({String currency = 'CNY'}) async {
    final ownerUserId = await _stamper.currentUserId();
    var inserted = 0;
    for (final seed in _kSystemAccountTreeSeeds) {
      final id = AccountRepository.systemAccountIdForPath(
        seed.path,
        ownerUserId: ownerUserId,
      );
      final existing = await (_db.select(
        _db.accounts,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing != null) continue;

      final stamp = await _stamper.stamp();
      const type = AccountCategory.asset;
      final name = seed.isRoot
          ? AccountRepository.systemAccountDisplayName(seed.category)
          : seed.name;
      final parentId = seed.parentPath == null
          ? null
          : AccountRepository.systemAccountIdForPath(
              seed.parentPath!,
              ownerUserId: ownerUserId,
            );
      final companion = AccountsCompanion.insert(
        id: id,
        type: type,
        name: name,
        currency: currency,
        category: Value(seed.category),
        parentId: Value(parentId),
        icon: Value(seed.icon),
        color: Value(seed.color),
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      );
      await _db.transaction(() async {
        await _db.into(_db.accounts).insert(companion);
        await _outbox.enqueue(table: AccountRepository._tableName, rowId: id);
        // Mirror the audit shape `create` uses so an account-history view
        // can replay system-account seeding the same way it replays user
        // account creates.
        await _eventLog.recordCreated(
          entityTable: AccountRepository._tableName,
          entityId: id,
          stamp: stamp,
          after: <String, Object?>{
            'type': type.name,
            'name': name,
            'currency': currency,
            'category': seed.category.name,
            'institution': null,
            'account_number': null,
            'note': null,
            'archived': false,
            'parent_id': parentId,
            'icon': seed.icon,
            'color': seed.color,
          },
        );
      });
      inserted++;
    }
    return inserted;
  }
}
