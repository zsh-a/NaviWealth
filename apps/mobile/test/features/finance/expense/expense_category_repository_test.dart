import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/expense/data/expense_category_repository.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category_presets.dart';

import '../../../core/persistence/test_database.dart';
import '../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
  });

  tearDown(() => db.close());

  test('default taxonomy seeds idempotently with a ledger bridge', () async {
    final stamper = makeStubStamper();
    final accounts = AccountRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    await accounts.seedSystemAccounts();
    final repository = ExpenseCategoryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );

    expect(
      await repository.seedDefaults('u-test'),
      kExpenseCategoryPresets.length,
    );
    expect(await repository.seedDefaults('u-test'), 0);

    final categories = await repository.watchActive('u-test').first;
    expect(categories, hasLength(kExpenseCategoryPresets.length));
    expect(
      categories.map((category) => category.ledgerAccountId).toSet(),
      hasLength(kExpenseCategoryPresets.length),
    );
    expect(
      categories.every(
        (category) => category.ledgerAccountId.startsWith(
          'system-account:u-test:expense:',
        ),
      ),
      isTrue,
    );
  });

  test('custom categories support edit, hierarchy and archive', () async {
    final repository = ExpenseCategoryRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
    final parent = await repository.create(name: 'Family');
    final child = await repository.create(
      name: 'Child care',
      parentId: parent.id,
    );

    final updated = await repository.update(
      id: child.id,
      name: 'Kids',
      parentId: parent.id,
      icon: 'gift',
      color: '#123456',
    );
    expect(updated.name, 'Kids');
    expect(updated.parentId, parent.id);
    expect(updated.icon, 'gift');
    expect(updated.color, '#123456');

    await expectLater(
      repository.setArchived(parent.id, archived: true),
      throwsStateError,
    );
    await repository.setArchived(child.id, archived: true);
    await repository.setArchived(parent.id, archived: true);
    expect(await repository.watchActive('u-test').first, isEmpty);
    expect(await repository.watchAll('u-test').first, hasLength(2));
  });

  test('owner-scoped reads never expose another user categories', () async {
    final first = ExpenseCategoryRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(userId: 'owner-a'),
    );
    final second = ExpenseCategoryRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(userId: 'owner-b'),
    );
    await first.create(name: 'A');
    await second.create(name: 'B');

    expect((await first.watchActive('owner-a').first).single.name, 'A');
    expect((await second.watchActive('owner-b').first).single.name, 'B');
  });
}
