import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:uuid/uuid.dart';

/// Read / write API for monthly category budgets
/// through the Finance-owned repository boundary.
///
/// Every mutation rides on the same sync envelope as the rest of the
/// SyncableTable family: write the row + enqueue a dirty pointer inside a
/// single Drift transaction so a crash between the two leaves the local
/// store in a consistent state.
class BudgetRepository {
  BudgetRepository({
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

  static const String _tableName = 'budgets';

  // ---------- Reads ----------

  /// Live stream of every non-deleted budget, ordered (periodMonth desc,
  /// categoryId asc) so the UI can group by month without re-sorting.
  Stream<List<BudgetRow>> watchAll() {
    final query = _db.select(_db.budgets)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.periodMonth, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.categoryId),
      ]);
    return query.watch();
  }

  /// All budgets for a single calendar month (`YYYY-MM`).
  Stream<List<BudgetRow>> watchByMonth(String periodMonth) {
    _requireMonth(periodMonth);
    final query = _db.select(_db.budgets)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.periodMonth.equals(periodMonth))
      ..orderBy([(t) => OrderingTerm(expression: t.categoryId)]);
    return query.watch();
  }

  Future<BudgetRow?> findForCategoryMonth({
    required String categoryId,
    required String periodMonth,
  }) async {
    _requireMonth(periodMonth);
    return (_db.select(_db.budgets)
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.categoryId.equals(categoryId))
          ..where((t) => t.periodMonth.equals(periodMonth)))
        .getSingleOrNull();
  }

  // ---------- Writes ----------

  /// Create a new budget. Throws if `(categoryId, periodMonth)` already
  /// has a live row — use [upsert] when overwriting is intentional.
  Future<BudgetRow> create({
    required String categoryId,
    required String periodMonth,
    required Decimal amount,
    required String currency,
    String? note,
  }) async {
    _requireMonth(periodMonth);
    _requireNonNegative(amount);
    final existing = await findForCategoryMonth(
      categoryId: categoryId,
      periodMonth: periodMonth,
    );
    if (existing != null) {
      throw StateError(
        'budget already exists for ($categoryId, $periodMonth); '
        'use upsert() to replace it',
      );
    }
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final companion = BudgetsCompanion.insert(
      id: id,
      categoryId: categoryId,
      periodMonth: periodMonth,
      amount: amount,
      currency: _normalizeCurrency(currency),
      note: Value(note),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    await _db.transaction(() async {
      await _db.into(_db.budgets).insert(companion);
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    return (await _byId(id))!;
  }

  /// Insert or replace the live row for `(categoryId, periodMonth)`.
  /// Returns the resulting row (created or updated).
  Future<BudgetRow> upsert({
    required String categoryId,
    required String periodMonth,
    required Decimal amount,
    required String currency,
    String? note,
  }) async {
    final existing = await findForCategoryMonth(
      categoryId: categoryId,
      periodMonth: periodMonth,
    );
    if (existing == null) {
      return create(
        categoryId: categoryId,
        periodMonth: periodMonth,
        amount: amount,
        currency: currency,
        note: note,
      );
    }
    return updateAmount(
      id: existing.id,
      amount: amount,
      currency: currency,
      note: note,
    );
  }

  /// Update an existing budget's amount / currency / note. The id, category,
  /// and period are immutable — moving a budget between months should be a
  /// delete + create so sync history reads cleanly.
  Future<BudgetRow> updateAmount({
    required String id,
    Decimal? amount,
    String? currency,
    String? note,
    bool clearNote = false,
  }) async {
    if (amount != null) _requireNonNegative(amount);
    final stamp = await _stamper.stamp();
    var pending = BudgetsCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    if (amount != null) pending = pending.copyWith(amount: Value(amount));
    if (currency != null) {
      pending = pending.copyWith(currency: Value(_normalizeCurrency(currency)));
    }
    if (clearNote) {
      pending = pending.copyWith(note: const Value(null));
    } else if (note != null) {
      pending = pending.copyWith(note: Value(note));
    }
    await _db.transaction(() async {
      await (_db.update(
        _db.budgets,
      )..where((t) => t.id.equals(id))).write(pending);
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    return (await _byId(id))!;
  }

  /// Soft-delete: writes a tombstone so peers learn about the removal via
  /// the next sync push.
  Future<void> delete(String id) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(_db.budgets)..where((t) => t.id.equals(id))).write(
        BudgetsCompanion(
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
          deletedAt: Value(stamp.now),
        ),
      );
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
  }

  Future<BudgetRow?> _byId(String id) => (_db.select(
    _db.budgets,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  static final RegExp _monthPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  static void _requireMonth(String periodMonth) {
    if (!_monthPattern.hasMatch(periodMonth)) {
      throw ArgumentError.value(
        periodMonth,
        'periodMonth',
        'must be YYYY-MM (e.g. 2026-05)',
      );
    }
  }

  static void _requireNonNegative(Decimal amount) {
    if (amount < Decimal.zero) {
      throw ArgumentError.value(amount, 'amount', 'must be non-negative');
    }
  }

  static String _normalizeCurrency(String code) {
    final trimmed = code.trim();
    if (trimmed.length < 3) {
      throw ArgumentError.value(code, 'currency', 'must be ≥ 3 chars');
    }
    return trimmed.toUpperCase();
  }
}
