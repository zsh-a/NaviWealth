import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../core/sync/op.dart';
import '../../core/sync/op_outbox.dart';
import '../db/app_database.dart';
import '../domain/expense_category.dart';
import '../domain/sync_meta.dart';
import 'mutation_context.dart';

/// FIR-68 — read/write API for [ExpenseCategory] rows.
///
/// Mirrors [AccountRepository]'s "row + outbox in one transaction" contract
/// so the local DB is always the durable source of queued sync ops. Default
/// categories use deterministic ids ([_defaultIdPrefix]) so re-seeding on
/// the same install — or seeding independently on multiple devices that
/// later sync — won't create duplicates.
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

  static const String _tableName = 'expense_categories';

  /// Stable id prefix for the seeded defaults. Keeps the seed idempotent
  /// across devices: every install resolves "餐饮" to the same id, so the
  /// LWW merge sees them as the same row.
  static const String _defaultIdPrefix = 'expense-cat-default:';

  /// The set seeded on first launch. Order is the display order users see
  /// in the picker; the seed writes `sortOrder` accordingly.
  static const List<DefaultExpenseCategorySeed> defaultSeeds = [
    DefaultExpenseCategorySeed(slug: 'food', name: '餐饮', icon: 'restaurant'),
    DefaultExpenseCategorySeed(
      slug: 'transport',
      name: '交通',
      icon: 'directions_car',
    ),
    DefaultExpenseCategorySeed(slug: 'rent', name: '房租', icon: 'home'),
    DefaultExpenseCategorySeed(
      slug: 'household',
      name: '居家',
      icon: 'chair',
    ),
    DefaultExpenseCategorySeed(
      slug: 'entertainment',
      name: '娱乐',
      icon: 'sports_esports',
    ),
    DefaultExpenseCategorySeed(
      slug: 'medical',
      name: '医疗',
      icon: 'local_hospital',
    ),
    DefaultExpenseCategorySeed(
      slug: 'education',
      name: '教育',
      icon: 'school',
    ),
    DefaultExpenseCategorySeed(
      slug: 'shopping',
      name: '购物',
      icon: 'shopping_bag',
    ),
    DefaultExpenseCategorySeed(slug: 'travel', name: '旅行', icon: 'flight'),
    DefaultExpenseCategorySeed(
      slug: 'communication',
      name: '通讯',
      icon: 'smartphone',
    ),
    DefaultExpenseCategorySeed(
      slug: 'gift',
      name: '礼物',
      icon: 'card_giftcard',
    ),
    DefaultExpenseCategorySeed(slug: 'other', name: '其它', icon: 'more_horiz'),
  ];

  static String defaultIdFor(String slug) => '$_defaultIdPrefix$slug';

  // ---------- Reads ----------

  /// Live stream of non-deleted, non-archived categories ordered by
  /// `sortOrder, name`. UIs use this for the expense entry picker.
  Stream<List<ExpenseCategory>> watchActive() {
    final query = _db.select(_db.expenseCategories)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.archivedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.name),
      ]);
    return query.watch().map((rows) => rows.map(_toCategory).toList());
  }

  Future<List<ExpenseCategory>> listActive() async {
    final rows =
        await (_db.select(_db.expenseCategories)
              ..where((t) => t.deletedAt.isNull())
              ..where((t) => t.archivedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.name),
              ]))
            .get();
    return rows.map(_toCategory).toList();
  }

  /// Includes archived rows (still hides tombstoned ones). Used by the
  /// management screen so users can un-archive.
  Future<List<ExpenseCategory>> listAllExceptDeleted() async {
    final rows =
        await (_db.select(_db.expenseCategories)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.name),
              ]))
            .get();
    return rows.map(_toCategory).toList();
  }

  /// Live stream variant of [listAllExceptDeleted]. Drives the management
  /// page so the archived section updates the moment a row is restored.
  /// Active rows come first (NULL `archivedAt` sorts before non-NULL); ties
  /// fall back to `sortOrder` then name so picker order stays stable.
  Stream<List<ExpenseCategory>> watchAllExceptDeleted() {
    final query = _db.select(_db.expenseCategories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.archivedAt),
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.name),
      ]);
    return query.watch().map((rows) => rows.map(_toCategory).toList());
  }

  Future<ExpenseCategory?> findById(String id) async {
    final row = await (_db.select(
      _db.expenseCategories,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toCategory(row);
  }

  // ---------- Writes ----------

  Future<ExpenseCategory> create({
    required String name,
    String? parentId,
    String? icon,
    String? color,
    int? sortOrder,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    return _insert(
      id: id,
      name: name,
      parentId: parentId,
      icon: icon,
      color: color,
      sortOrder: sortOrder,
      stamp: stamp,
    );
  }

  Future<ExpenseCategory> update(
    String id, {
    String? name,
    String? parentId,
    bool clearParent = false,
    String? icon,
    bool clearIcon = false,
    String? color,
    bool clearColor = false,
    int? sortOrder,
    bool clearSortOrder = false,
  }) async {
    final stamp = await _stamper.stamp();
    final diff = <String, Object?>{};
    var pending = ExpenseCategoriesCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    if (name != null) {
      pending = pending.copyWith(name: Value(name));
      diff['name'] = name;
    }
    if (clearParent) {
      pending = pending.copyWith(parentId: const Value(null));
      diff['parent_id'] = null;
    } else if (parentId != null) {
      pending = pending.copyWith(parentId: Value(parentId));
      diff['parent_id'] = parentId;
    }
    if (clearIcon) {
      pending = pending.copyWith(icon: const Value(null));
      diff['icon'] = null;
    } else if (icon != null) {
      pending = pending.copyWith(icon: Value(icon));
      diff['icon'] = icon;
    }
    if (clearColor) {
      pending = pending.copyWith(color: const Value(null));
      diff['color'] = null;
    } else if (color != null) {
      pending = pending.copyWith(color: Value(color));
      diff['color'] = color;
    }
    if (clearSortOrder) {
      pending = pending.copyWith(sortOrder: const Value(null));
      diff['sort_order'] = null;
    } else if (sortOrder != null) {
      pending = pending.copyWith(sortOrder: Value(sortOrder));
      diff['sort_order'] = sortOrder;
    }
    if (diff.isEmpty) return (await findById(id))!;
    diff['updated_at'] = stamp.now.toUtc().toIso8601String();
    diff['updated_by_device'] = stamp.deviceId;
    diff['hlc'] = stamp.hlc.toString();
    await _db.transaction(() async {
      await (_db.update(
        _db.expenseCategories,
      )..where((t) => t.id.equals(id))).write(pending);
      await _enqueue(
        opType: OpType.update,
        rowId: id,
        fields: diff,
        stamp: stamp,
      );
    });
    return (await findById(id))!;
  }

  /// User-archives a category. The row is hidden from picker defaults but
  /// still resolvable by id (existing expenses keep rendering correctly)
  /// and still synced.
  Future<ExpenseCategory> archive(String id) => _setArchived(id, archived: true);

  Future<ExpenseCategory> unarchive(String id) =>
      _setArchived(id, archived: false);

  /// Soft-delete: writes a tombstone and queues a `delete` op. Existing
  /// expenses tagged with this category continue to resolve `categoryId`
  /// to the deleted row (UI is expected to fall back to "其它" or show the
  /// original name).
  Future<void> softDelete(String id) async {
    final stamp = await _stamper.stamp();
    final companion = ExpenseCategoriesCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
      deletedAt: Value(stamp.now),
    );
    await _db.transaction(() async {
      await (_db.update(
        _db.expenseCategories,
      )..where((t) => t.id.equals(id))).write(companion);
      await _enqueue(
        opType: OpType.delete,
        rowId: id,
        fields: null,
        stamp: stamp,
      );
    });
  }

  /// Inserts the [defaultSeeds] using deterministic ids. Idempotent:
  /// re-running won't create duplicates because the deterministic id is
  /// the primary key. Newly-seeded rows still queue insert ops so peers
  /// that have never seen them (e.g. a fresh device that gets sync'd
  /// before its own seed runs) will pick them up.
  ///
  /// Returns the *number of rows actually inserted* (0 on a no-op call),
  /// so callers can decide whether to surface a "defaults seeded" toast.
  Future<int> seedDefaults() async {
    var inserted = 0;
    for (var i = 0; i < defaultSeeds.length; i++) {
      final seed = defaultSeeds[i];
      final id = defaultIdFor(seed.slug);
      final existing = await (_db.select(
        _db.expenseCategories,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing != null) continue;
      final stamp = await _stamper.stamp();
      await _insert(
        id: id,
        name: seed.name,
        icon: seed.icon,
        color: seed.color,
        sortOrder: i,
        stamp: stamp,
      );
      inserted++;
    }
    return inserted;
  }

  // ---------- Internals ----------

  Future<ExpenseCategory> _insert({
    required String id,
    required String name,
    String? parentId,
    String? icon,
    String? color,
    int? sortOrder,
    required MutationStamp stamp,
  }) async {
    final companion = ExpenseCategoriesCompanion.insert(
      id: id,
      name: name,
      parentId: Value(parentId),
      icon: Value(icon),
      color: Value(color),
      sortOrder: Value(sortOrder),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    final fields = <String, Object?>{
      'id': id,
      'name': name,
      'parent_id': parentId,
      'icon': icon,
      'color': color,
      'sort_order': sortOrder,
      'owner_user_id': stamp.ownerUserId,
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
    await _db.transaction(() async {
      await _db.into(_db.expenseCategories).insert(companion);
      await _enqueue(
        opType: OpType.insert,
        rowId: id,
        fields: fields,
        stamp: stamp,
      );
    });
    return (await findById(id))!;
  }

  Future<ExpenseCategory> _setArchived(
    String id, {
    required bool archived,
  }) async {
    final stamp = await _stamper.stamp();
    final companion = ExpenseCategoriesCompanion(
      archivedAt: Value(archived ? stamp.now : null),
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    final diff = <String, Object?>{
      'archived_at': archived ? stamp.now.toUtc().toIso8601String() : null,
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
    await _db.transaction(() async {
      await (_db.update(
        _db.expenseCategories,
      )..where((t) => t.id.equals(id))).write(companion);
      await _enqueue(
        opType: OpType.update,
        rowId: id,
        fields: diff,
        stamp: stamp,
      );
    });
    return (await findById(id))!;
  }

  Future<void> _enqueue({
    required OpType opType,
    required String rowId,
    required Map<String, Object?>? fields,
    required MutationStamp stamp,
  }) async {
    final op = Op(
      opId: _uuid.v4(),
      tableName: _tableName,
      rowId: rowId,
      opType: opType,
      fieldsDiff: fields,
      hlc: stamp.hlc,
      deviceId: stamp.deviceId,
    );
    await _outbox.enqueue(op);
  }

  ExpenseCategory _toCategory(ExpenseCategoryRow row) {
    return ExpenseCategory(
      id: row.id,
      name: row.name,
      parentId: row.parentId,
      icon: row.icon,
      color: row.color,
      sortOrder: row.sortOrder,
      archivedAt: row.archivedAt,
      sync: SyncMeta(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
        deletedAt: row.deletedAt,
      ),
    );
  }
}

/// Static description of a default-seeded expense category.
class DefaultExpenseCategorySeed {
  const DefaultExpenseCategorySeed({
    required this.slug,
    required this.name,
    this.icon,
    this.color,
  });

  /// Stable suffix used to derive the deterministic id; never changes once
  /// shipped (renaming a slug would orphan every existing row pointing at
  /// the old id on already-installed devices).
  final String slug;
  final String name;
  final String? icon;
  final String? color;
}
