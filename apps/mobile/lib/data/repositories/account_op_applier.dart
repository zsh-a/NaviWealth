import 'package:drift/drift.dart';

import '../../core/sync/op.dart';
import '../../core/sync/op_applier.dart';
import '../db/app_database.dart';
import '../domain/enums.dart';

/// Applies pulled `accounts` ops to the local Drift table.
///
/// Local writes already go through [AccountRepository]. This adapter is the
/// peer path: it trusts the server-stamped HLC on each op and applies a
/// row-level LWW check before mutating the materialised table.
class AccountOpApplier implements OpApplier {
  AccountOpApplier(this._db);

  final AppDatabase _db;

  @override
  Future<void> applyAll(List<Op> ops) async {
    if (ops.isEmpty) return;
    await _db.transaction(() async {
      for (final op in ops) {
        if (op.tableName != 'accounts') continue;
        await _apply(op);
      }
    });
  }

  Future<void> _apply(Op op) async {
    final existing = await (_db.select(
      _db.accounts,
    )..where((t) => t.id.equals(op.rowId))).getSingleOrNull();
    if (existing != null && existing.hlc >= op.hlc) {
      return;
    }

    switch (op.opType) {
      case OpType.insert:
        await _upsertFromFields(op, existing: existing);
      case OpType.update:
        if (existing == null) {
          // A reset-to-zero cursor normally fetches the insert first. If an
          // update somehow arrives before its base row, keep the cycle
          // retryable instead of advancing the cursor past unapplied data.
          throw StateError('account update before insert: ${op.rowId}');
        }
        await _updateFromDiff(op);
      case OpType.delete:
        if (existing == null) return;
        await (_db.update(
          _db.accounts,
        )..where((t) => t.id.equals(op.rowId))).write(
          AccountsCompanion(
            updatedAt: Value(op.hlc.wallTime),
            updatedByDevice: Value(op.deviceId),
            hlc: Value(op.hlc),
            deletedAt: Value(op.hlc.wallTime),
          ),
        );
    }
  }

  Future<void> _upsertFromFields(Op op, {required AccountRow? existing}) async {
    final fields = _fields(op);
    final type = _accountType(_requiredString(fields, 'type'));
    final companion = AccountsCompanion.insert(
      id: _string(fields, 'id') ?? op.rowId,
      type: type,
      name: _requiredString(fields, 'name'),
      currency: _requiredString(fields, 'currency'),
      category: Value(
        _accountCategory(fields['category'] as String?) ??
            defaultCategoryForAccountType(type),
      ),
      institution: Value(_string(fields, 'institution')),
      accountNumber: Value(_string(fields, 'account_number')),
      note: Value(_string(fields, 'note')),
      archived: Value(_bool(fields, 'archived') ?? false),
      parentId: Value(_string(fields, 'parent_id')),
      icon: Value(_string(fields, 'icon')),
      color: Value(_string(fields, 'color')),
      ownerUserId: _requiredString(fields, 'owner_user_id'),
      updatedAt: op.hlc.wallTime,
      updatedByDevice: op.deviceId,
      hlc: op.hlc,
      deletedAt: const Value(null),
    );

    if (existing == null) {
      await _db.into(_db.accounts).insert(companion);
    } else {
      await (_db.update(
        _db.accounts,
      )..where((t) => t.id.equals(op.rowId))).write(companion);
    }
  }

  Future<void> _updateFromDiff(Op op) async {
    final fields = _fields(op);
    var companion = AccountsCompanion(
      updatedAt: Value(op.hlc.wallTime),
      updatedByDevice: Value(op.deviceId),
      hlc: Value(op.hlc),
      deletedAt: const Value(null),
    );
    if (fields.containsKey('type')) {
      companion = companion.copyWith(
        type: Value(_accountType(_requiredString(fields, 'type'))),
      );
    }
    if (fields.containsKey('name')) {
      companion = companion.copyWith(
        name: Value(_requiredString(fields, 'name')),
      );
    }
    if (fields.containsKey('currency')) {
      companion = companion.copyWith(
        currency: Value(_requiredString(fields, 'currency')),
      );
    }
    if (fields.containsKey('category')) {
      companion = companion.copyWith(
        category: Value(_accountCategory(fields['category'] as String?)!),
      );
    }
    if (fields.containsKey('institution')) {
      companion = companion.copyWith(
        institution: Value(_string(fields, 'institution')),
      );
    }
    if (fields.containsKey('account_number')) {
      companion = companion.copyWith(
        accountNumber: Value(_string(fields, 'account_number')),
      );
    }
    if (fields.containsKey('note')) {
      companion = companion.copyWith(note: Value(_string(fields, 'note')));
    }
    if (fields.containsKey('archived')) {
      companion = companion.copyWith(
        archived: Value(_bool(fields, 'archived') ?? false),
      );
    }
    if (fields.containsKey('parent_id')) {
      companion = companion.copyWith(
        parentId: Value(_string(fields, 'parent_id')),
      );
    }
    if (fields.containsKey('icon')) {
      companion = companion.copyWith(icon: Value(_string(fields, 'icon')));
    }
    if (fields.containsKey('color')) {
      companion = companion.copyWith(color: Value(_string(fields, 'color')));
    }

    await (_db.update(
      _db.accounts,
    )..where((t) => t.id.equals(op.rowId))).write(companion);
  }

  Map<String, Object?> _fields(Op op) {
    final fields = op.fieldsDiff;
    if (fields == null) {
      throw StateError('account ${op.opType.name} missing fields_diff');
    }
    return fields;
  }

  String _requiredString(Map<String, Object?> fields, String key) {
    final value = _string(fields, key);
    if (value == null || value.isEmpty) {
      throw StateError('account op missing required field: $key');
    }
    return value;
  }

  String? _string(Map<String, Object?> fields, String key) {
    final value = fields[key];
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  bool? _bool(Map<String, Object?> fields, String key) {
    final value = fields[key];
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    throw StateError('account op field $key is not bool: $value');
  }

  AccountType _accountType(String value) {
    return AccountType.values.byName(value);
  }

  AccountCategory? _accountCategory(String? value) {
    if (value == null || value.isEmpty) return null;
    return AccountCategory.values.byName(value);
  }
}
