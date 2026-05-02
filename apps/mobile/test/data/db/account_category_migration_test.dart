import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';

import 'test_database.dart';

/// FIR-126 v8 migration: covers [backfillAccountCategory], the helper that
/// rewrites every existing `accounts.category` value from the prior
/// `accounts.type` carrier shape.
///
/// We exercise the helper directly against a v8 in-memory database that
/// we hand-seed with rows whose `category` would have been the column
/// default (`asset`) on a v7 → v8 upgrade. That keeps the test
/// independent of drift's `Migrator.fromVersion` plumbing while still
/// asserting the behaviour the migration cares about — that liability
/// carriers flip to the `liability` category and every other carrier is
/// left as `asset`.
void main() {
  late AppDatabase db;

  setUp(() {
    db = makeTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertAccount({
    required String id,
    required AccountType type,
    AccountCategory? category,
  }) async {
    final hlc = Hlc(
      wallMillis: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'd1',
    );
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: id,
            type: type,
            name: id,
            currency: 'CNY',
            // Mirror the v8 onUpgrade column-default: every row starts as
            // `asset`, the backfill is what flips the liability rows.
            category: Value(category ?? AccountCategory.asset),
            ownerUserId: 'u1',
            updatedAt: DateTime.utc(2026, 1, 1),
            updatedByDevice: 'd1',
            hlc: hlc,
          ),
        );
  }

  test('liability carriers flip to AccountCategory.liability', () async {
    await insertAccount(id: 'acc-bank', type: AccountType.bank);
    await insertAccount(id: 'acc-brokerage', type: AccountType.brokerage);
    await insertAccount(id: 'acc-crypto', type: AccountType.cryptoWallet);
    await insertAccount(id: 'acc-cash', type: AccountType.cash);
    await insertAccount(id: 'acc-realestate', type: AccountType.realEstate);
    await insertAccount(id: 'acc-vehicle', type: AccountType.vehicle);
    await insertAccount(id: 'acc-other', type: AccountType.other);
    await insertAccount(id: 'acc-liability', type: AccountType.liability);

    await backfillAccountCategory(db);

    Future<AccountCategory> categoryFor(String id) async {
      final row = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals(id))).getSingle();
      return row.category;
    }

    expect(await categoryFor('acc-bank'), AccountCategory.asset);
    expect(await categoryFor('acc-brokerage'), AccountCategory.asset);
    expect(await categoryFor('acc-crypto'), AccountCategory.asset);
    expect(await categoryFor('acc-cash'), AccountCategory.asset);
    expect(await categoryFor('acc-realestate'), AccountCategory.asset);
    expect(await categoryFor('acc-vehicle'), AccountCategory.asset);
    expect(await categoryFor('acc-other'), AccountCategory.asset);
    expect(await categoryFor('acc-liability'), AccountCategory.liability);
  });

  test(
    'backfill is idempotent — rerunning leaves the category unchanged',
    () async {
      await insertAccount(id: 'acc-bank', type: AccountType.bank);
      await insertAccount(id: 'acc-liability', type: AccountType.liability);

      await backfillAccountCategory(db);
      await backfillAccountCategory(db);

      final rows = await db.select(db.accounts).get();
      expect(
        {for (final r in rows) r.id: r.category},
        {
          'acc-bank': AccountCategory.asset,
          'acc-liability': AccountCategory.liability,
        },
      );
    },
  );

  test(
    'a row that was hand-edited to a non-default category before the '
    'backfill ran still gets reconciled when the carrier is liability',
    () async {
      // Edge case: an install that pre-shipped FIR-126 (e.g. tests, internal
      // dogfood) might already have a row with category = expense on a
      // liability carrier. The backfill is intentionally an unconditional
      // UPDATE, so it overwrites these rows back to the canonical value.
      // We document that here so future maintainers understand the
      // trade-off if the rule ever needs to soften.
      await insertAccount(
        id: 'acc-edited',
        type: AccountType.liability,
        category: AccountCategory.expense,
      );
      await backfillAccountCategory(db);
      final row = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('acc-edited'))).getSingle();
      expect(row.category, AccountCategory.liability);
    },
  );

  test('defaultCategoryForAccountType matches the migration rule', () {
    // The form's "default-from-type" suggestion and the v8 backfill both
    // live behind the same heuristic. Cross-check them so a future change
    // doesn't drift one without the other.
    expect(
      defaultCategoryForAccountType(AccountType.bank),
      AccountCategory.asset,
    );
    expect(
      defaultCategoryForAccountType(AccountType.liability),
      AccountCategory.liability,
    );
    for (final t in AccountType.values) {
      final expected = t == AccountType.liability
          ? AccountCategory.liability
          : AccountCategory.asset;
      expect(defaultCategoryForAccountType(t), expected, reason: t.name);
    }
  });
}
