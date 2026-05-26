import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/invariants.dart';
import 'package:naviwealth/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/data/repositories/price_repository.dart';

import '../../core/persistence/test_database.dart';
import '_stub_stamper.dart';

class _IdentityFx implements FxRateSource {
  const _IdentityFx();

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) {
    return Decimal.one;
  }
}

void main() {
  late AppDatabase db;
  late PriceRepository priceRepo;
  late JournalEntryRepository journalEntryRepo;
  late ManualAssetRepository repo;

  setUp(() async {
    db = makeTestDatabase();
    final outbox = InMemoryOutboxStore();
    priceRepo = PriceRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
    journalEntryRepo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
      fxRateSource: const _IdentityFx(),
      baseCurrency: 'CNY',
    );
    repo = ManualAssetRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
      priceRepo: priceRepo,
      journalEntryRepo: journalEntryRepo,
    );
    await _insertAccount(db, id: 'acc-cash', currency: 'CNY');
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'createCash records the balance as real currency in the account',
    () async {
      final asset = await repo.createCash(
        accountId: 'acc-cash',
        currency: 'CNY',
        balance: Decimal.parse('100'),
        nickname: 'Wallet',
      );

      final accountPostings = await _accountPostings(db, 'acc-cash');
      expect(accountPostings, hasLength(1));
      expect(accountPostings.single.unit, 'CNY');
      expect(accountPostings.single.units, Decimal.parse('100'));

      final latest = await priceRepo.latestAt(
        unit: asset.id,
        quoteCurrency: 'CNY',
        asOf: DateTime.now().toUtc(),
      );
      expect(latest?.perUnit, Decimal.parse('100'));
    },
  );

  test('cash valuation adjustments post only the balance delta', () async {
    final asset = await repo.createCash(
      accountId: 'acc-cash',
      currency: 'CNY',
      balance: Decimal.parse('100'),
    );

    await repo.recordValuationAdjust(
      assetId: asset.id,
      newValuation: Decimal.parse('250'),
    );

    final accountPostings = await _accountPostings(db, 'acc-cash');
    expect(accountPostings.map((p) => p.unit).toSet(), {'CNY'});
    expect(
      accountPostings.map((p) => p.units),
      unorderedEquals([Decimal.parse('100'), Decimal.parse('150')]),
    );
    expect(
      accountPostings.fold<Decimal>(
        Decimal.zero,
        (sum, posting) => sum + posting.units,
      ),
      Decimal.parse('250'),
    );
  });

  test('cash balance can be adjusted down to zero', () async {
    final asset = await repo.createCash(
      accountId: 'acc-cash',
      currency: 'CNY',
      balance: Decimal.parse('100'),
    );

    await repo.recordValuationAdjust(
      assetId: asset.id,
      newValuation: Decimal.zero,
    );

    final accountPostings = await _accountPostings(db, 'acc-cash');
    expect(
      accountPostings.map((p) => p.units),
      unorderedEquals([Decimal.parse('100'), Decimal.parse('-100')]),
    );
    final latest = await priceRepo.latestAt(
      unit: asset.id,
      quoteCurrency: 'CNY',
      asOf: DateTime.now().toUtc(),
    );
    expect(latest?.perUnit, Decimal.zero);
  });

  test('createCash preserves an explicit zero balance valuation', () async {
    final asset = await repo.createCash(
      accountId: 'acc-cash',
      currency: 'CNY',
      balance: Decimal.zero,
    );

    expect(await _accountPostings(db, 'acc-cash'), isEmpty);
    final latest = await priceRepo.latestAt(
      unit: asset.id,
      quoteCurrency: 'CNY',
      asOf: DateTime.now().toUtc(),
    );
    expect(latest?.perUnit, Decimal.zero);
  });

  test(
    'cash balance ignores security quantity postings on same account',
    () async {
      final cash = await repo.createCash(
        accountId: 'acc-cash',
        currency: 'CNY',
        balance: Decimal.parse('10000'),
      );
      final buy = JournalEntryBuilders.buy(
        date: DateTime.utc(2026, 5, 13),
        accountId: 'acc-cash',
        cashAccountId: 'acc-cash',
        assetUnit: 'cn_a:600519',
        qty: Decimal.parse('10'),
        price: Decimal.parse('100'),
        quoteCurrency: 'CNY',
      );

      await journalEntryRepo.create(entry: buy.entry, postings: buy.postings);

      final rawAccountTotal = (await _accountPostings(
        db,
        'acc-cash',
      )).fold<Decimal>(Decimal.zero, (sum, posting) => sum + posting.units);
      expect(rawAccountTotal, Decimal.parse('9010'));
      expect(
        await repo.cashBalanceFromPostings(cash.id),
        Decimal.parse('9000'),
      );
    },
  );
}

Future<List<PostingRow>> _accountPostings(AppDatabase db, String accountId) {
  final query = db.select(db.postings)
    ..where((t) => t.accountId.equals(accountId))
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm(expression: t.position)]);
  return query.get();
}

Future<void> _insertAccount(
  AppDatabase db, {
  required String id,
  required String currency,
}) {
  return db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          id: id,
          type: AccountCategory.cash,
          name: 'Cash',
          currency: currency,
          category: const Value(AccountSide.asset),
          ownerUserId: 'u-test',
          updatedAt: DateTime.utc(2026),
          updatedByDevice: 'dev-test',
          hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
        ),
      );
}
