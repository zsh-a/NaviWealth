import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/repositories/budget_repository.dart';

import '../db/test_database.dart';
import '_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late BudgetRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = BudgetRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() => db.close());

  test('create persists a budget and enqueues a sync dirty pointer', () async {
    final row = await repo.create(
      categoryId: 'cat-food',
      periodMonth: '2026-05',
      amount: Decimal.parse('1500.00'),
      currency: 'cny',
      note: 'eating out cap',
    );
    expect(row.categoryId, 'cat-food');
    expect(row.periodMonth, '2026-05');
    expect(row.amount, Decimal.parse('1500.00'));
    expect(row.currency, 'CNY', reason: 'currency is uppercased');
    expect(row.note, 'eating out cap');
    expect(row.deletedAt, isNull);

    final enqueued = await outbox.depth();
    expect(enqueued, 1, reason: 'one dirty pointer for sync');
  });

  test('create rejects duplicate (categoryId, periodMonth)', () async {
    await repo.create(
      categoryId: 'cat-rent',
      periodMonth: '2026-05',
      amount: Decimal.parse('5000'),
      currency: 'CNY',
    );
    await expectLater(
      () => repo.create(
        categoryId: 'cat-rent',
        periodMonth: '2026-05',
        amount: Decimal.parse('6000'),
        currency: 'CNY',
      ),
      throwsStateError,
    );
  });

  test('upsert replaces an existing budget in place', () async {
    final first = await repo.upsert(
      categoryId: 'cat-rent',
      periodMonth: '2026-05',
      amount: Decimal.parse('5000'),
      currency: 'CNY',
    );
    final replaced = await repo.upsert(
      categoryId: 'cat-rent',
      periodMonth: '2026-05',
      amount: Decimal.parse('5500'),
      currency: 'CNY',
      note: 'rent hike',
    );
    expect(replaced.id, first.id, reason: 'same id is reused');
    expect(replaced.amount, Decimal.parse('5500'));
    expect(replaced.note, 'rent hike');

    final live = await repo.findForCategoryMonth(
      categoryId: 'cat-rent',
      periodMonth: '2026-05',
    );
    expect(live?.id, first.id);
    expect(live?.amount, Decimal.parse('5500'));
  });

  test('updateAmount applies partial diffs without touching unspecified fields', () async {
    final created = await repo.create(
      categoryId: 'cat-food',
      periodMonth: '2026-05',
      amount: Decimal.parse('1000'),
      currency: 'CNY',
      note: 'keep me',
    );
    final updated = await repo.updateAmount(
      id: created.id,
      amount: Decimal.parse('1200'),
    );
    expect(updated.amount, Decimal.parse('1200'));
    expect(updated.note, 'keep me', reason: 'untouched field survives');
    expect(updated.currency, 'CNY');
  });

  test('updateAmount clearNote removes the note', () async {
    final created = await repo.create(
      categoryId: 'cat-food',
      periodMonth: '2026-05',
      amount: Decimal.parse('1000'),
      currency: 'CNY',
      note: 'will be cleared',
    );
    final updated = await repo.updateAmount(
      id: created.id,
      clearNote: true,
    );
    expect(updated.note, isNull);
  });

  test('delete sets a tombstone and excludes from watchAll', () async {
    final created = await repo.create(
      categoryId: 'cat-food',
      periodMonth: '2026-05',
      amount: Decimal.parse('1000'),
      currency: 'CNY',
    );
    await repo.delete(created.id);

    final alive = await repo.watchAll().first;
    expect(alive, isEmpty);

    final byKey = await repo.findForCategoryMonth(
      categoryId: 'cat-food',
      periodMonth: '2026-05',
    );
    expect(byKey, isNull, reason: 'findForCategoryMonth ignores tombstones');
  });

  test('periodMonth must be canonical YYYY-MM', () async {
    await expectLater(
      () => repo.create(
        categoryId: 'cat-food',
        periodMonth: '2026/05',
        amount: Decimal.parse('100'),
        currency: 'CNY',
      ),
      throwsArgumentError,
    );
    await expectLater(
      () => repo.create(
        categoryId: 'cat-food',
        periodMonth: '2026-13',
        amount: Decimal.parse('100'),
        currency: 'CNY',
      ),
      throwsArgumentError,
    );
  });

  test('amount must be non-negative', () async {
    await expectLater(
      () => repo.create(
        categoryId: 'cat-food',
        periodMonth: '2026-05',
        amount: Decimal.parse('-1'),
        currency: 'CNY',
      ),
      throwsArgumentError,
    );
  });

  test('watchByMonth filters by the requested month', () async {
    await repo.create(
      categoryId: 'cat-food',
      periodMonth: '2026-04',
      amount: Decimal.parse('1000'),
      currency: 'CNY',
    );
    await repo.create(
      categoryId: 'cat-food',
      periodMonth: '2026-05',
      amount: Decimal.parse('1100'),
      currency: 'CNY',
    );
    await repo.create(
      categoryId: 'cat-rent',
      periodMonth: '2026-05',
      amount: Decimal.parse('5000'),
      currency: 'CNY',
    );

    final may = await repo.watchByMonth('2026-05').first;
    expect(may, hasLength(2));
    expect(
      may.map((b) => b.categoryId).toSet(),
      {'cat-food', 'cat-rent'},
    );
  });
}
