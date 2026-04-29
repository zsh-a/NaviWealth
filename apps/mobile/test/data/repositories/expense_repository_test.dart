import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/expense_metadata.dart';
import 'package:naviwealth/data/repositories/account_repository.dart';
import 'package:naviwealth/data/repositories/expense_category_repository.dart';
import 'package:naviwealth/data/repositories/expense_repository.dart';

import '../db/test_database.dart';
import '_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late ExpenseRepository repo;
  late AccountRepository accountRepo;
  late ExpenseCategoryRepository categoryRepo;
  late String accountId;
  late String categoryId;

  setUp(() async {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    accountRepo = AccountRepository(db: db, outbox: outbox, stamper: stamper);
    categoryRepo = ExpenseCategoryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    repo = ExpenseRepository(db: db, outbox: outbox, stamper: stamper);
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

  test('create writes a negative-quantity transaction with metadata',
      () async {
    final expense = await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('120.50'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 4, 30),
      tags: const ['lunch'],
      note: 'team lunch',
    );

    expect(expense.amount, Decimal.parse('120.50'));
    expect(expense.categoryId, categoryId);
    expect(expense.tags, ['lunch']);
    expect(expense.note, 'team lunch');

    // The underlying transaction stores the quantity signed-negative so
    // SUM(quantity * price) over the account folds into the right cash
    // outflow without needing per-type sign logic.
    final raw = await db
        .customSelect(
          'SELECT type, quantity, price, currency, expense_metadata_json '
          'FROM transactions WHERE id = ?',
          variables: [Variable.withString(expense.id)],
        )
        .getSingle();
    expect(raw.read<String>('type'), 'expense');
    expect(Decimal.parse(raw.read<String>('quantity')), Decimal.parse('-120.50'));
    expect(Decimal.parse(raw.read<String>('price')), Decimal.one);
    expect(raw.read<String>('currency'), 'CNY');
    final metadata = ExpenseMetadata.decode(
      raw.read<String?>('expense_metadata_json'),
    );
    expect(metadata!.categoryId, categoryId);
    expect(metadata.tags, ['lunch']);
  });

  test('create rejects zero or negative amount', () async {
    expect(
      () => repo.create(
        accountId: accountId,
        categoryId: categoryId,
        amount: Decimal.zero,
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 4, 30),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.create(
        accountId: accountId,
        categoryId: categoryId,
        amount: Decimal.parse('-1'),
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 4, 30),
      ),
      throwsArgumentError,
    );
  });

  test('cross-currency expense (USD account / CNY spend) is preserved',
      () async {
    final usd = await accountRepo.create(
      type: AccountType.bank,
      name: 'US Checking',
      currency: 'USD',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final exp = await repo.create(
      accountId: usd.id,
      categoryId: categoryId,
      amount: Decimal.parse('88.00'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 4, 30),
    );

    expect(exp.currency, 'CNY');
    expect(exp.amount, Decimal.parse('88.00'));
    final reload = await repo.findById(exp.id);
    expect(reload!.currency, 'CNY');
    // Account currency stays USD; we never overwrite it from the expense.
    final acc = await accountRepo.findById(usd.id);
    expect(acc!.currency, 'USD');
  });

  test('update only diffs the changed fields and re-encodes metadata',
      () async {
    final exp = await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('50'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 4, 1),
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final newCategory = await categoryRepo.create(name: '交通');
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final updated = await repo.update(
      exp.id,
      amount: Decimal.parse('75'),
      categoryId: newCategory.id,
      tags: const ['taxi'],
    );

    expect(updated.amount, Decimal.parse('75'));
    expect(updated.categoryId, newCategory.id);
    expect(updated.tags, ['taxi']);

    final op = (await outbox.peekBatch()).single;
    expect(op.opType, OpType.update);
    final diff = op.fieldsDiff!;
    expect(diff['quantity'], '-75');
    expect(diff.containsKey('expense_metadata_json'), isTrue);
    final encoded = diff['expense_metadata_json']! as String;
    final meta = ExpenseMetadata.decode(encoded)!;
    expect(meta.categoryId, newCategory.id);
    expect(meta.tags, ['taxi']);
    // Trade date wasn't touched.
    expect(diff.containsKey('trade_date'), isFalse);
  });

  test('update preserves existing tags when only categoryId is changed',
      () async {
    final exp = await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('10'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 4, 1),
      tags: const ['recurring', 'subscription'],
    );
    final newCategory = await categoryRepo.create(name: '订阅');
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final updated = await repo.update(exp.id, categoryId: newCategory.id);
    expect(updated.tags, ['recurring', 'subscription']);
  });

  test('softDelete tombstones the expense and queues a delete op', () async {
    final exp = await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('30'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 4, 1),
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    await repo.softDelete(exp.id);
    final reloaded = await repo.findById(exp.id);
    expect(reloaded!.sync.deletedAt, isNotNull);

    final op = (await outbox.peekBatch()).single;
    expect(op.opType, OpType.delete);
    expect(op.fieldsDiff, isNull);

    // listExpenses must filter the tombstoned row.
    final live = await repo.listExpenses();
    expect(live, isEmpty);
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
    await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('15'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 4, 10),
    );
    await repo.create(
      accountId: other.id,
      categoryId: categoryId,
      amount: Decimal.parse('99'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 4, 10),
    );

    // Take the first non-empty snapshot for this account.
    final snapshot = await stream
        .firstWhere((rows) => rows.isNotEmpty);
    expect(snapshot.length, 1);
    expect(snapshot.single.accountId, accountId);
  });

  test('listExpenses filters by date range', () async {
    await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('1'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 3, 31),
    );
    await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('2'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 4, 15),
    );
    await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('3'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 5, 1),
    );

    final april = await repo.listExpenses(
      from: DateTime.utc(2026, 4, 1),
      to: DateTime.utc(2026, 5, 1),
    );
    expect(april.map((e) => e.amount), [Decimal.parse('2')]);
  });

  test('insert op carries a JSON-decodable expense metadata blob '
      '(sync round trip)', () async {
    final exp = await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('42'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 4, 30),
      tags: const ['cafe'],
      note: 'morning coffee',
    );

    // Round-trip the queued op through its wire encoding to mirror what the
    // server sees on push and what peers replay on pull.
    final op = (await outbox.peekBatch()).single;
    final wire = op.encode();
    final decodedOp = Op.decode(wire);
    expect(decodedOp.tableName, 'transactions');
    expect(decodedOp.opType, OpType.insert);
    expect(decodedOp.rowId, exp.id);
    final fields = decodedOp.fieldsDiff!;
    expect(fields['type'], 'expense');
    expect(fields['quantity'], '-42');
    expect(fields['currency'], 'CNY');
    final meta = ExpenseMetadata.decode(
      fields['expense_metadata_json']! as String,
    );
    expect(meta!.categoryId, categoryId);
    expect(meta.tags, ['cafe']);
  });

  test('expense outflow rolls into account cash flow via signed quantity',
      () async {
    // Drop a deposit + two expenses on the same account.
    await db.into(db.transactions).insert(
          await _depositCompanion(
            db: db,
            accountId: accountId,
            amount: Decimal.parse('500'),
          ),
        );
    await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('120'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 4, 10),
    );
    await repo.create(
      accountId: accountId,
      categoryId: categoryId,
      amount: Decimal.parse('80'),
      currency: 'CNY',
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
    // SQLite returns SUM(REAL) as a double; Drift surfaces it via read<double>.
    final net = row.read<double>('net');
    // 500 - 120 - 80 = 300 — proves the negative-quantity convention
    // composes with existing cash flows without per-type knowledge.
    expect(net, closeTo(300.0, 0.0001));
  });
}

/// Test-only helper: forge a "deposit" transaction directly so the cash-flow
/// roll-up assertion has a positive baseline to fold the expenses against.
/// Bypasses the repo on purpose — there is no DepositRepository yet, but
/// the math we're asserting only depends on the table shape.
Future<TransactionsCompanion> _depositCompanion({
  required AppDatabase db,
  required String accountId,
  required Decimal amount,
}) async {
  // Use a constant HLC + owner so the row passes NOT NULL constraints.
  // The actual values don't matter for the SUM assertion above.
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

