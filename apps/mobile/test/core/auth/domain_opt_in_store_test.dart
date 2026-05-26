import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';

import '../../core/persistence/test_database.dart';

void main() {
  group('DomainOptInStore', () {
    test('returns financeOnly on a fresh database', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = DomainOptInStore(db);
      expect(await store.read(), DomainOptIns.financeOnly);
    });

    test('round-trips through write / read', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = DomainOptInStore(db);

      final updated = DomainOptIns.financeOnly
          .withScope(DomainScope.health, enabled: true);
      await store.write(updated);

      expect(await store.read(), updated);
    });

    test('disabling health falls back to financeOnly', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = DomainOptInStore(db);

      await store.write(
        DomainOptIns.financeOnly.withScope(DomainScope.health, enabled: true),
      );
      await store.write(DomainOptIns.financeOnly);

      expect(await store.read(), DomainOptIns.financeOnly);
    });
  });
}
