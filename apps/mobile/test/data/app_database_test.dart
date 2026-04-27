import 'package:decimal/decimal.dart';
// Drift exports its own `isNull` SQL helper that collides with the matcher
// of the same name; hide drift's variant so test assertions read naturally.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // In-memory NativeDatabase keeps the schema test fast and hermetic;
    // there's no migration concern at v1 yet so we just `createAll`.
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('schema creates all tables and round-trips a transaction row', () async {
    const hlc = Hlc(wallMillis: 1000, counter: 0, nodeId: 'd1');
    final updatedAt = DateTime.utc(2026, 1, 1);

    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: 'tx-1',
            accountId: 'acc-1',
            type: TransactionType.buy,
            quantity: Decimal.parse('10.5'),
            price: Decimal.parse('123.4567'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 1),
            ownerUserId: 'u1',
            updatedAt: updatedAt,
            updatedByDevice: 'd1',
            hlc: hlc,
          ),
        );

    final row = await db.select(db.transactions).getSingle();
    expect(row.id, 'tx-1');
    expect(row.type, TransactionType.buy);
    // Decimal precision must survive the TEXT round trip — losing it here
    // would silently corrupt cost basis math, so it's the most important
    // invariant to assert.
    expect(row.quantity, Decimal.parse('10.5'));
    expect(row.price, Decimal.parse('123.4567'));
    expect(row.hlc, hlc);
    expect(row.deletedAt, isNull);
  });

  test('soft delete is queryable via deletedAt filter', () async {
    const hlc = Hlc(wallMillis: 1000, counter: 0, nodeId: 'd1');
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'a1',
            type: AccountType.brokerage,
            name: 'Live',
            currency: 'USD',
            ownerUserId: 'u1',
            updatedAt: DateTime.utc(2026, 1, 1),
            updatedByDevice: 'd1',
            hlc: hlc,
          ),
        );
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'a2',
            type: AccountType.brokerage,
            name: 'Tombstoned',
            currency: 'USD',
            ownerUserId: 'u1',
            updatedAt: DateTime.utc(2026, 1, 1),
            updatedByDevice: 'd1',
            hlc: hlc,
            deletedAt: Value(DateTime.utc(2026, 2, 1)),
          ),
        );

    final live = await (db.select(
      db.accounts,
    )..where((t) => t.deletedAt.isNull())).get();
    expect(live.map((r) => r.id).toSet(), {'a1'});
  });
}
