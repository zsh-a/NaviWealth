import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/account_repository.dart';
import '../mappers/account_mapper.dart';

class DriftAccountRepository implements AccountRepository {
  DriftAccountRepository(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$AccountsTable, AccountRow> _baseQuery({
    required bool includeArchived,
  }) {
    final query = _db.select(_db.accounts)..where((t) => t.deletedAt.isNull());
    if (!includeArchived) {
      query.where((t) => t.archived.equals(0));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.name)]);
    return query;
  }

  @override
  Future<List<Account>> listAll({bool includeArchived = false}) async {
    final rows = await _baseQuery(includeArchived: includeArchived).get();
    return rows.map(accountFromRow).toList();
  }

  @override
  Stream<List<Account>> watchAll({bool includeArchived = false}) {
    return _baseQuery(
      includeArchived: includeArchived,
    ).watch().map((rows) => rows.map(accountFromRow).toList());
  }

  @override
  Future<Account?> findById(String id) async {
    final row = await (_db.select(
      _db.accounts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : accountFromRow(row);
  }

  @override
  Future<void> upsert(Account account) async {
    await _db
        .into(_db.accounts)
        .insertOnConflictUpdate(accountToCompanion(account));
  }

  @override
  Future<void> archive(String id) async {
    await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        archived: const Value(1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  @override
  Future<void> softDelete(String id) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
