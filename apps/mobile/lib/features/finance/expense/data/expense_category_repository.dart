import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:uuid/uuid.dart';

import '../domain/expense_category.dart';
import '../domain/expense_category_presets.dart';

class ExpenseCategoryRepository {
  ExpenseCategoryRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  static const _categoryTable = 'categories';
  static const _accountTable = 'accounts';
  static const _categoryIdPrefix = 'expense-category:';

  static String systemCategoryId(String ownerUserId, String systemKey) =>
      '$_categoryIdPrefix$ownerUserId:$systemKey';

  Stream<List<ExpenseCategory>> watchActive(String ownerUserId) {
    final query = _db.select(_db.categories)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.archived.equals(false))
      ..where((t) => t.mergedIntoId.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.name),
      ]);
    return query.watch().map(_mapRows);
  }

  Stream<List<ExpenseCategory>> watchAll(String ownerUserId) {
    final query = _db.select(_db.categories)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.mergedIntoId.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.name),
      ]);
    return query.watch().map(_mapRows);
  }

  Future<ExpenseCategory?> findById(String ownerUserId, String id) async {
    final row =
        await (_db.select(_db.categories)
              ..where((t) => t.ownerUserId.equals(ownerUserId))
              ..where((t) => t.id.equals(id))
              ..where((t) => t.deletedAt.isNull()))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<ExpenseCategory?> findByLedgerAccountId(
    String ownerUserId,
    String ledgerAccountId,
  ) async {
    final row =
        await (_db.select(_db.categories)
              ..where((t) => t.ownerUserId.equals(ownerUserId))
              ..where((t) => t.ledgerAccountId.equals(ledgerAccountId))
              ..where((t) => t.deletedAt.isNull()))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<int> seedDefaults(String ownerUserId) async {
    var inserted = 0;
    for (var index = 0; index < kExpenseCategoryPresets.length; index++) {
      final preset = kExpenseCategoryPresets[index];
      final id = systemCategoryId(ownerUserId, preset.key);
      final exists = await (_db.select(
        _db.categories,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (exists != null) continue;

      final stamp = await _stamper.stamp();
      if (stamp.ownerUserId != ownerUserId) {
        throw StateError('Expense category owner mismatch.');
      }
      final ledgerAccountId = AccountRepository.systemAccountIdForPath(
        'expense:${preset.key}',
        ownerUserId: ownerUserId,
      );
      final parentLedgerAccountId = AccountRepository.systemAccountIdForPath(
        preset.parentKey == null ? 'expense' : 'expense:${preset.parentKey}',
        ownerUserId: ownerUserId,
      );
      final parentCategoryId = preset.parentKey == null
          ? null
          : systemCategoryId(ownerUserId, preset.parentKey!);
      final accountExists = await (_db.select(
        _db.accounts,
      )..where((t) => t.id.equals(ledgerAccountId))).getSingleOrNull();

      await _db.transaction(() async {
        if (accountExists == null) {
          await _db
              .into(_db.accounts)
              .insert(
                AccountsCompanion.insert(
                  id: ledgerAccountId,
                  type: AccountCategory.asset,
                  name: preset.nameEn,
                  currency: 'CNY',
                  category: const Value(AccountSide.expense),
                  parentId: Value(parentLedgerAccountId),
                  icon: Value(preset.icon),
                  color: Value(preset.color),
                  ownerUserId: stamp.ownerUserId,
                  updatedAt: stamp.now,
                  updatedByDevice: stamp.deviceId,
                  hlc: stamp.hlc,
                ),
              );
          await _outbox.enqueue(table: _accountTable, rowId: ledgerAccountId);
        }
        await _db
            .into(_db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: id,
                name: preset.nameEn,
                systemKey: Value(preset.key),
                parentId: Value(parentCategoryId),
                ledgerAccountId: ledgerAccountId,
                icon: Value(preset.icon),
                color: Value(preset.color),
                sortOrder: Value(index),
                ownerUserId: stamp.ownerUserId,
                updatedAt: stamp.now,
                updatedByDevice: stamp.deviceId,
                hlc: stamp.hlc,
              ),
            );
        await _outbox.enqueue(table: _categoryTable, rowId: id);
      });
      inserted++;
    }
    return inserted;
  }

  Future<ExpenseCategory> create({
    required String name,
    String? parentId,
    String? icon,
    String? color,
  }) async {
    final normalizedName = _requireName(name);
    final stamp = await _stamper.stamp();
    final ownerUserId = stamp.ownerUserId;
    final parent = parentId == null
        ? null
        : await _requireOwned(ownerUserId, parentId);
    final id = _uuid.v4();
    final ledgerAccountId = AccountRepository.systemAccountIdForPath(
      'expense:custom:$id',
      ownerUserId: ownerUserId,
    );
    final rootAccountId = AccountRepository.systemAccountIdForPath(
      'expense',
      ownerUserId: ownerUserId,
    );
    final sortOrder = await _nextSortOrder(ownerUserId);

    await _db.transaction(() async {
      await _db
          .into(_db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: ledgerAccountId,
              type: AccountCategory.asset,
              name: normalizedName,
              currency: 'CNY',
              category: const Value(AccountSide.expense),
              parentId: Value(parent?.ledgerAccountId ?? rootAccountId),
              icon: Value(icon ?? 'category'),
              color: Value(color),
              ownerUserId: ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _db
          .into(_db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: id,
              name: normalizedName,
              parentId: Value(parentId),
              ledgerAccountId: ledgerAccountId,
              icon: Value(icon ?? 'category'),
              color: Value(color),
              sortOrder: Value(sortOrder),
              ownerUserId: ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _outbox.enqueue(table: _accountTable, rowId: ledgerAccountId);
      await _outbox.enqueue(table: _categoryTable, rowId: id);
    });
    return (await findById(ownerUserId, id))!;
  }

  Future<ExpenseCategory> update({
    required String id,
    required String name,
    String? parentId,
    String? icon,
    String? color,
    int? sortOrder,
  }) async {
    final normalizedName = _requireName(name);
    final stamp = await _stamper.stamp();
    final current = await _requireOwned(stamp.ownerUserId, id);
    if (parentId == id) throw ArgumentError('A category cannot parent itself.');
    final parent = parentId == null
        ? null
        : await _requireOwned(stamp.ownerUserId, parentId);
    if (parent != null && await _isDescendant(current.id, parent.id)) {
      throw ArgumentError('A category cannot move below its descendant.');
    }
    final rootAccountId = AccountRepository.systemAccountIdForPath(
      'expense',
      ownerUserId: stamp.ownerUserId,
    );
    final categoryWrite = CategoriesCompanion(
      name: current.isBuiltIn ? Value(current.name) : Value(normalizedName),
      nameOverride: current.isBuiltIn
          ? Value(normalizedName)
          : const Value.absent(),
      parentId: Value(parentId),
      icon: Value(icon),
      color: Value(color),
      sortOrder: Value(sortOrder ?? current.sortOrder),
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    await _db.transaction(() async {
      await (_db.update(
        _db.categories,
      )..where((t) => t.id.equals(id))).write(categoryWrite);
      await (_db.update(
        _db.accounts,
      )..where((t) => t.id.equals(current.ledgerAccountId))).write(
        AccountsCompanion(
          name: Value(normalizedName),
          parentId: Value(parent?.ledgerAccountId ?? rootAccountId),
          icon: Value(icon),
          color: Value(color),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: _categoryTable, rowId: id);
      await _outbox.enqueue(
        table: _accountTable,
        rowId: current.ledgerAccountId,
      );
    });
    return (await findById(stamp.ownerUserId, id))!;
  }

  Future<void> setArchived(String id, {required bool archived}) async {
    final stamp = await _stamper.stamp();
    final current = await _requireOwned(stamp.ownerUserId, id);
    if (archived) {
      final activeChild =
          await (_db.select(_db.categories)
                ..where((t) => t.ownerUserId.equals(stamp.ownerUserId))
                ..where((t) => t.parentId.equals(id))
                ..where((t) => t.deletedAt.isNull())
                ..where((t) => t.archived.equals(false))
                ..limit(1))
              .getSingleOrNull();
      if (activeChild != null) {
        throw StateError('Archive child categories first.');
      }
    }
    await _db.transaction(() async {
      await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(
          archived: Value(archived),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await (_db.update(
        _db.accounts,
      )..where((t) => t.id.equals(current.ledgerAccountId))).write(
        AccountsCompanion(
          archived: Value(archived),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: _categoryTable, rowId: id);
      await _outbox.enqueue(
        table: _accountTable,
        rowId: current.ledgerAccountId,
      );
    });
  }

  Future<void> setSortOrder(String id, int sortOrder) async {
    final stamp = await _stamper.stamp();
    await _requireOwned(stamp.ownerUserId, id);
    await _db.transaction(() async {
      await (_db.update(_db.categories)
            ..where((t) => t.ownerUserId.equals(stamp.ownerUserId))
            ..where((t) => t.id.equals(id)))
          .write(
            CategoriesCompanion(
              sortOrder: Value(sortOrder),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
      await _outbox.enqueue(table: _categoryTable, rowId: id);
    });
  }

  Future<ExpenseCategory> _requireOwned(String ownerUserId, String id) async {
    final category = await findById(ownerUserId, id);
    if (category == null) throw StateError('Expense category not found.');
    return category;
  }

  Future<bool> _isDescendant(String rootId, String candidateId) async {
    var cursor = await (_db.select(
      _db.categories,
    )..where((t) => t.id.equals(candidateId))).getSingleOrNull();
    var hops = 0;
    while (cursor != null && hops < 64) {
      if (cursor.parentId == rootId) return true;
      final parentId = cursor.parentId;
      if (parentId == null) return false;
      cursor = await (_db.select(
        _db.categories,
      )..where((t) => t.id.equals(parentId))).getSingleOrNull();
      hops++;
    }
    return false;
  }

  Future<int> _nextSortOrder(String ownerUserId) async {
    final rows = await (_db.select(
      _db.categories,
    )..where((t) => t.ownerUserId.equals(ownerUserId))).get();
    var maxOrder = -1;
    for (final row in rows) {
      final value = row.sortOrder;
      if (value > maxOrder) maxOrder = value;
    }
    return maxOrder + 1;
  }

  static String _requireName(String value) {
    final name = value.trim();
    if (name.isEmpty) throw ArgumentError.value(value, 'name', 'is required');
    return name;
  }

  List<ExpenseCategory> _mapRows(List<CategoryRow> rows) =>
      rows.map(_toDomain).toList(growable: false);

  ExpenseCategory _toDomain(CategoryRow row) => ExpenseCategory(
    id: row.id,
    name: row.name,
    nameOverride: row.nameOverride,
    systemKey: row.systemKey,
    parentId: row.parentId,
    ledgerAccountId: row.ledgerAccountId,
    icon: row.icon,
    color: row.color,
    sortOrder: row.sortOrder,
    archived: row.archived,
    mergedIntoId: row.mergedIntoId,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
      deletedAt: row.deletedAt,
    ),
  );
}
