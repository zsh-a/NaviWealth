import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/expense_metadata.dart';
import 'package:naviwealth/data/repositories/account_repository.dart';
import 'package:naviwealth/data/repositories/expense_category_repository.dart';
import 'package:naviwealth/data/repositories/expense_repository.dart';
import 'package:naviwealth/data/repositories/mutation_context.dart';
import 'package:uuid/uuid.dart';

import '../db/test_database.dart';
import '_stub_stamper.dart';

/// FIR-131 wave 3h — `ExpenseRepository` is now a read-only view over
/// `transactions WHERE type='expense'`. All write paths (`create`,
/// `update`, `softDelete`) flow through the journal-entry stack.
///
/// These tests exercise the remaining surface (`watchExpenses`,
/// `listExpenses`, signed-quantity cash-flow roll-up) using the
/// [_insertLegacyExpense] helper to seed rows directly via Drift.
Future<String> _insertLegacyExpense({
  required AppDatabase db,
  required MutationStamper stamper,
  required String accountId,
  required String categoryId,
  required Decimal amount,
  String currency = 'CNY',
  required DateTime tradeDate,
  List<String> tags = const [],
  String? note,
}) async {
  final id = const Uuid().v4();
  final metadata = ExpenseMetadata(categoryId: categoryId, tags: tags);
  final stamp = await stamper.stamp();
  await db.into(db.transactions).insert(
    TransactionsCompanion.insert(
      id: id,
      accountId: accountId,
      type: TransactionType.expense,
      quantity: -amount,
      price: Decimal.one,
      currency: currency,
      tradeDate: tradeDate,
      note: Value(note),
      expenseMetadataJson: Value(metadata.encode()),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    ),
  );
  return id;
}

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late MutationStamper stamper;
  late ExpenseRepository repo;
  late AccountRepository accountRepo;
  late ExpenseCategoryRepository categoryRepo;
  late String accountId;
  late String categoryId;

  setUp(() async {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    stamper = makeStubStamper();
    accountRepo = AccountRepository(db: db, outbox: outbox, stamper: stamper);
    categoryRepo = ExpenseCategoryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    repo = ExpenseRepository(db: db);
    final acc = await accountRepo.create(
      type: AccountType.cash,
      name: '现金',
      currency: 'CNY',
    );
    accountId = acc.id;
    final cat = await categoryRepo.create(name: '餐饮');
    categoryId = cat.id;
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());
  });

  tearDown(() async {
    await db.close();
  });

  test('watchExpenses streams new and updated rows scoped by account',
      () async {
    final other = await accountRepo.create(
      type: AccountType.bank,
      name: 'other',
      currency: 'CNY',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final stream = repo.watchExpenses(accountId: accountId);
    await _insertLegacyExpense(
      db: db,
      stamper: stamper,
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('15'),
      tradeDate: DateTime.utc(2026, 4, 10),
    );
    await _insertLegacyExpense(
      db: db,
      stamper: stamper,
      accountId: other.id,
      categoryId: categoryId,
      amount: Decimal.parse('99'),
      tradeDate: DateTime.utc(2026, 4, 10),
    );

    final snapshot = await stream.firstWhere((rows) => rows.isNotEmpty);
    expect(snapshot.length, 1);
    expect(snapshot.single.accountId, accountId);
  });

  test('listExpenses filters by date range', () async {
    await _insertLegacyExpense(
      db: db,
      stamper: stamper,
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('1'),
      tradeDate: DateTime.utc(2026, 3, 31),
    );
    await _insertLegacyExpense(
      db: db,
      stamper: stamper,
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('2'),
      tradeDate: DateTime.utc(2026, 4, 15),
    );
    await _insertLegacyExpense(
      db: db,
      stamper: stamper,
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('3'),
      tradeDate: DateTime.utc(2026, 5, 1),
    );

    final april = await repo.listExpenses(
      from: DateTime.utc(2026, 4, 1),
      to: DateTime.utc(2026, 5, 1),
    );
    expect(april.map((e) => e.amount), [Decimal.parse('2')]);
  });

  test('expense outflow rolls into account cash flow via signed quantity',
      () async {
    await db.into(db.transactions).insert(
          await _depositCompanion(
            db: db,
            accountId: accountId,
            amount: Decimal.parse('500'),
          ),
        );
    await _insertLegacyExpense(
      db: db,
      stamper: stamper,
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('120'),
      tradeDate: DateTime.utc(2026, 4, 10),
    );
    await _insertLegacyExpense(
      db: db,
      stamper: stamper,
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('80'),
      tradeDate: DateTime.utc(2026, 4, 11),
    );

    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(CAST(quantity AS REAL) * CAST(price AS REAL)), 0)'
          ' AS net FROM transactions'
          ' WHERE account_id = ? AND deleted_at IS NULL',
          variables: [Variable.withString(accountId)],
        )
        .getSingle();
    final net = row.read<double>('net');
    // 500 - 120 - 80 = 300 — proves the negative-quantity convention
    // composes with existing cash flows without per-type knowledge.
    expect(net, closeTo(300.0, 0.0001));
  });
}

/// Test-only helper: forge a "deposit" transaction directly so the cash-flow
/// roll-up assertion has a positive baseline to fold the expenses against.
Future<TransactionsCompanion> _depositCompanion({
  required AppDatabase db,
  required String accountId,
  required Decimal amount,
}) async {
  final stamp = await makeStubStamper(initialMillis: 1_700_001_000_000).stamp();
  return TransactionsCompanion.insert(
    id: 'tx-deposit-${stamp.now.microsecondsSinceEpoch}',
    accountId: accountId,
    type: TransactionType.deposit,
    quantity: amount,
    price: Decimal.one,
    currency: 'CNY',
    tradeDate: DateTime.utc(2026, 4, 1),
    ownerUserId: stamp.ownerUserId,
    updatedAt: stamp.now,
    updatedByDevice: stamp.deviceId,
    hlc: stamp.hlc,
  );
}
