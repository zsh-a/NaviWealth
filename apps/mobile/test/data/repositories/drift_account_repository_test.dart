import 'package:flutter_test/flutter_test.dart';

import 'package:naviwealth/data/repositories/drift_account_repository.dart';
import 'package:naviwealth/domain/entities/account.dart';

import '../../core/db/test_database.dart';

void main() {
  group('DriftAccountRepository', () {
    late final fixedNow = DateTime.utc(2026, 1, 15, 12);

    Account makeAccount({
      String id = 'acc-1',
      String name = '招行储蓄',
      AccountKind kind = AccountKind.bank,
      String currency = 'CNY',
      bool archived = false,
    }) {
      return Account(
        id: id,
        name: name,
        kind: kind,
        currency: currency,
        openingBalance: 0,
        createdAt: fixedNow,
        updatedAt: fixedNow,
        archived: archived,
      );
    }

    test('upsert + listAll round-trips an account', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repo = DriftAccountRepository(db);

      await repo.upsert(makeAccount());
      final all = await repo.listAll();

      expect(all, hasLength(1));
      expect(all.single.id, 'acc-1');
      expect(all.single.kind, AccountKind.bank);
      expect(all.single.currency, 'CNY');
    });

    test('upsert overwrites an existing row by id', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repo = DriftAccountRepository(db);

      await repo.upsert(makeAccount(name: 'old'));
      await repo.upsert(makeAccount(name: 'new'));

      final all = await repo.listAll();
      expect(all, hasLength(1));
      expect(all.single.name, 'new');
    });

    test('archive hides the account from default listAll', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repo = DriftAccountRepository(db);

      await repo.upsert(makeAccount(id: 'a'));
      await repo.upsert(makeAccount(id: 'b', name: 'b'));
      await repo.archive('a');

      final visible = await repo.listAll();
      expect(visible.map((a) => a.id), ['b']);

      final all = await repo.listAll(includeArchived: true);
      expect(all.map((a) => a.id).toSet(), {'a', 'b'});
      final archived = all.firstWhere((a) => a.id == 'a');
      expect(archived.archived, isTrue);
    });

    test('softDelete excludes the row from all listAll variants', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repo = DriftAccountRepository(db);

      await repo.upsert(makeAccount());
      await repo.softDelete('acc-1');

      expect(await repo.listAll(), isEmpty);
      expect(await repo.listAll(includeArchived: true), isEmpty);
    });

    test('watchAll emits updates when rows change', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repo = DriftAccountRepository(db);

      final stream = repo.watchAll();
      final emissions = <List<Account>>[];
      final sub = stream.listen(emissions.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(Duration.zero);
      await repo.upsert(makeAccount());
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, hasLength(1));
      expect(emissions.last.single.id, 'acc-1');
    });
  });
}
