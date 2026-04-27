import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';
import '../../domain/entities/account.dart';

AccountKind _kindFromString(String value) {
  return AccountKind.values.firstWhere(
    (k) => k.name == value,
    orElse: () => AccountKind.other,
  );
}

Account accountFromRow(AccountRow row) {
  return Account(
    id: row.id,
    name: row.name,
    kind: _kindFromString(row.kind),
    currency: row.currency,
    openingBalance: row.openingBalance,
    institution: row.institution,
    notes: row.notes,
    archived: row.archived != 0,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );
}

AccountsCompanion accountToCompanion(Account a) {
  return AccountsCompanion.insert(
    id: a.id,
    name: a.name,
    kind: a.kind.name,
    currency: a.currency,
    openingBalance: Value(a.openingBalance),
    institution: Value(a.institution),
    notes: Value(a.notes),
    archived: Value(a.archived ? 1 : 0),
    createdAt: a.createdAt,
    updatedAt: a.updatedAt,
    deletedAt: Value(a.deletedAt),
  );
}
