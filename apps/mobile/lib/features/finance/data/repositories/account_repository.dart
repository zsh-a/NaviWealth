import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/audit/event_log_writer.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:uuid/uuid.dart';

part 'account_repository_system_accounts.dart';
part 'account_repository_system_account_seeds.dart';
part 'account_repository_tree.dart';

/// Read/write API for [Account] rows.
///
/// Every mutation lives in a Drift transaction that *both* writes the row
/// and marks it dirty in the sync outbox. The two writes committing together
/// is what makes the local store durable — if the process crashes between
/// them, the row is rolled back and the user sees the failure rather than a
/// silently un-synced change.
class AccountRepository {
  AccountRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    EventLogWriter? eventLog,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _eventLog = eventLog ?? EventLogWriter(db: db, uuid: uuid),
       _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final EventLogWriter _eventLog;
  final Uuid _uuid;

  static const String _tableName = 'accounts';

  // ---------- Reads ----------

  /// Live stream of non-archived, non-deleted accounts ordered by name.
  ///
  /// Virtual system accounts (`system-account:*`) are filtered
  /// out so they never appear in the user-facing list / picker. They
  /// remain queryable via [findById] and through the system-account
  /// helpers on this repository — the caller doing posting work always
  /// resolves them deliberately, so hiding them everywhere else keeps the
  /// "real account" surface from getting cluttered.
  Stream<List<Account>> watchActive() {
    final query = _db.select(_db.accounts)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.archived.equals(false))
      ..where((t) => t.id.like('$_systemAccountIdPrefix%').not())
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    return query.watch().map((rows) => rows.map(_toAccount).toList());
  }

  /// Like [watchActive] but includes system accounts. Used by the expense
  /// category picker which needs to display seeded system expense accounts.
  Stream<List<Account>> watchActiveIncludingSystem() {
    final query = _db.select(_db.accounts)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.archived.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    return query.watch().map((rows) => rows.map(_toAccount).toList());
  }

  Future<List<Account>> listActive() async {
    final rows =
        await (_db.select(_db.accounts)
              ..where((t) => t.deletedAt.isNull())
              ..where((t) => t.archived.equals(false))
              ..where((t) => t.id.like('$_systemAccountIdPrefix%').not())
              ..orderBy([(t) => OrderingTerm(expression: t.name)]))
            .get();
    return rows.map(_toAccount).toList();
  }

  Future<Account?> findById(String id) async {
    final row = await (_db.select(
      _db.accounts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toAccount(row);
  }

  // ---------- Writes ----------

  Future<Account> create({
    required AccountCategory type,
    required String name,
    required String currency,
    AccountSide? category,
    String? institution,
    String? accountNumber,
    String? note,
    String? parentId,
    String? icon,
    String? color,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final resolvedCategory = category ?? accountSideForCategory(type);
    final companion = AccountsCompanion.insert(
      id: id,
      type: type,
      name: name,
      currency: currency,
      category: Value(resolvedCategory),
      institution: Value(institution),
      accountNumber: Value(accountNumber),
      note: Value(note),
      parentId: Value(parentId),
      icon: Value(icon),
      color: Value(color),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    await _db.transaction(() async {
      await _db.into(_db.accounts).insert(companion);
      await _outbox.enqueue(table: _tableName, rowId: id);
      await _eventLog.recordCreated(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        after: <String, Object?>{
          'type': type.name,
          'name': name,
          'currency': currency,
          'category': resolvedCategory.name,
          'institution': institution,
          'account_number': accountNumber,
          'note': note,
          'archived': false,
          'parent_id': parentId,
          'icon': icon,
          'color': color,
        },
      );
    });
    return (await findById(id))!;
  }

  /// Updates only the named fields. Returns the refreshed [Account].
  ///
  /// Sync semantics: the write marks the row dirty; the sync engine pushes
  /// the row's whole current state and peers apply row-level LWW
  /// (`docs/sync/sync-v2.md` §6).
  Future<Account> update(
    String id, {
    String? name,
    String? currency,
    AccountSide? category,
    String? institution,
    bool? clearInstitution,
    String? accountNumber,
    bool? clearAccountNumber,
    String? note,
    bool? clearNote,
    bool? archived,
    String? parentId,
    bool? clearParentId,
    String? icon,
    bool? clearIcon,
    String? color,
    bool? clearColor,
    String? reason,
  }) async {
    final stamp = await _stamper.stamp();
    final diff = <String, Object?>{};
    final companion = AccountsCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    var pending = companion;
    if (name != null) {
      pending = pending.copyWith(name: Value(name));
      diff['name'] = name;
    }
    if (currency != null) {
      pending = pending.copyWith(currency: Value(currency));
      diff['currency'] = currency;
    }
    if (category != null) {
      pending = pending.copyWith(category: Value(category));
      diff['category'] = category.name;
    }
    if (clearInstitution == true) {
      pending = pending.copyWith(institution: const Value(null));
      diff['institution'] = null;
    } else if (institution != null) {
      pending = pending.copyWith(institution: Value(institution));
      diff['institution'] = institution;
    }
    if (clearAccountNumber == true) {
      pending = pending.copyWith(accountNumber: const Value(null));
      diff['account_number'] = null;
    } else if (accountNumber != null) {
      pending = pending.copyWith(accountNumber: Value(accountNumber));
      diff['account_number'] = accountNumber;
    }
    if (clearNote == true) {
      pending = pending.copyWith(note: const Value(null));
      diff['note'] = null;
    } else if (note != null) {
      pending = pending.copyWith(note: Value(note));
      diff['note'] = note;
    }
    if (archived != null) {
      pending = pending.copyWith(archived: Value(archived));
      diff['archived'] = archived;
    }
    if (clearParentId == true) {
      pending = pending.copyWith(parentId: const Value(null));
      diff['parent_id'] = null;
    } else if (parentId != null) {
      pending = pending.copyWith(parentId: Value(parentId));
      diff['parent_id'] = parentId;
    }
    if (clearIcon == true) {
      pending = pending.copyWith(icon: const Value(null));
      diff['icon'] = null;
    } else if (icon != null) {
      pending = pending.copyWith(icon: Value(icon));
      diff['icon'] = icon;
    }
    if (clearColor == true) {
      pending = pending.copyWith(color: const Value(null));
      diff['color'] = null;
    } else if (color != null) {
      pending = pending.copyWith(color: Value(color));
      diff['color'] = color;
    }
    if (diff.isEmpty) {
      // Nothing to do — the protocol rejects empty updates and we'd rather
      // surface this as "noop" than let the caller queue a stale op.
      return (await findById(id))!;
    }
    diff['updated_at'] = stamp.now.toUtc().toIso8601String();
    diff['updated_by_device'] = stamp.deviceId;
    diff['hlc'] = stamp.hlc.toString();

    await _db.transaction(() async {
      // Capture prior values *for the changed columns only* before
      // writing — so the audit row has a faithful before/after pair
      // for every key in the diff. We re-read inside the txn so a
      // concurrent writer can't race the snapshot.
      final priorRow = await (_db.select(
        _db.accounts,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      await (_db.update(
        _db.accounts,
      )..where((t) => t.id.equals(id))).write(pending);
      await _outbox.enqueue(table: _tableName, rowId: id);
      if (priorRow != null) {
        final auditBefore = <String, Object?>{};
        final auditAfter = <String, Object?>{};
        if (diff.containsKey('name')) {
          auditBefore['name'] = priorRow.name;
          auditAfter['name'] = diff['name'];
        }
        if (diff.containsKey('currency')) {
          auditBefore['currency'] = priorRow.currency;
          auditAfter['currency'] = diff['currency'];
        }
        if (diff.containsKey('category')) {
          auditBefore['category'] = priorRow.category.name;
          auditAfter['category'] = diff['category'];
        }
        if (diff.containsKey('institution')) {
          auditBefore['institution'] = priorRow.institution;
          auditAfter['institution'] = diff['institution'];
        }
        if (diff.containsKey('account_number')) {
          auditBefore['account_number'] = priorRow.accountNumber;
          auditAfter['account_number'] = diff['account_number'];
        }
        if (diff.containsKey('note')) {
          auditBefore['note'] = priorRow.note;
          auditAfter['note'] = diff['note'];
        }
        if (diff.containsKey('archived')) {
          auditBefore['archived'] = priorRow.archived;
          auditAfter['archived'] = diff['archived'];
        }
        if (diff.containsKey('parent_id')) {
          auditBefore['parent_id'] = priorRow.parentId;
          auditAfter['parent_id'] = diff['parent_id'];
        }
        if (diff.containsKey('icon')) {
          auditBefore['icon'] = priorRow.icon;
          auditAfter['icon'] = diff['icon'];
        }
        if (diff.containsKey('color')) {
          auditBefore['color'] = priorRow.color;
          auditAfter['color'] = diff['color'];
        }
        if (auditAfter.isNotEmpty) {
          await _eventLog.recordFieldChanged(
            entityTable: _tableName,
            entityId: id,
            stamp: stamp,
            before: auditBefore,
            after: auditAfter,
            reason: reason,
          );
        }
      }
    });
    return (await findById(id))!;
  }

  /// Soft-delete: writes a tombstone (`deletedAt = now`) and queues a
  /// `delete` op. Peers honour the tombstone via LWW.
  Future<void> softDelete(String id, {String? reason}) async {
    final stamp = await _stamper.stamp();
    final companion = AccountsCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
      deletedAt: Value(stamp.now),
    );
    await _db.transaction(() async {
      await (_db.update(
        _db.accounts,
      )..where((t) => t.id.equals(id))).write(companion);
      await _outbox.enqueue(table: _tableName, rowId: id);
      await _eventLog.recordSoftDeleted(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        reason: reason,
      );
    });
  }

  // ---------- Helpers ----------

  Account _toAccount(AccountRow row) {
    return Account(
      id: row.id,
      type: row.type,
      name: row.name,
      currency: row.currency,
      category: row.category,
      institution: row.institution,
      accountNumber: row.accountNumber,
      note: row.note,
      archived: row.archived,
      parentId: row.parentId,
      icon: row.icon,
      color: row.color,
      sync: SyncMeta(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
        deletedAt: row.deletedAt,
      ),
    );
  }

  // ---------- System / virtual accounts ----------

  /// Stable id prefix for the seeded system accounts. Keeps the seed
  /// idempotent across devices: every install resolves the same path to
  /// the same id, so the LWW merge never duplicates them.
  static const String _systemAccountIdPrefix = 'system-account:';

  /// Path segments for the seeded root system accounts. Asset / liability
  /// accounts represent real balances the user owns, so we never
  /// auto-seed those; the income / expense / equity buckets are abstract
  /// counter-accounts the double-entry posting model needs as default
  /// targets for cash flows that don't terminate on a real account.
  static const List<AccountSide> systemAccountCategories = [
    AccountSide.income,
    AccountSide.expense,
    AccountSide.equity,
  ];

  /// Resolves any system-account `id` from a `:`-separated [path] under
  /// the user's stable prefix. Roots use `category.name` as the path
  /// (e.g. `income`); leaves under a root use `parent:leaf` (e.g.
  /// `income:salary`, `expense:trading:fee`).
  static String systemAccountIdForPath(
    String path, {
    required String ownerUserId,
  }) => '$_systemAccountIdPrefix$ownerUserId:$path';

  /// Convenience for the three root system accounts.
  /// Prefer [systemAccountIdForPath] for deeper nodes.
  static String systemAccountIdFor(
    AccountSide category, {
    required String ownerUserId,
  }) => systemAccountIdForPath(category.name, ownerUserId: ownerUserId);

  /// Display name for one of the three root system accounts. Kept in
  /// Chinese (the app's primary locale today) so the picker labels look
  /// natural without an l10n round-trip; child accounts seeded
  /// use the canonical Beancount-style English names from
  /// [_kSystemAccountTreeSeeds] — the UI localises at render time.
  static String systemAccountDisplayName(AccountSide category) {
    switch (category) {
      case AccountSide.income:
        return '系统收入账户';
      case AccountSide.expense:
        return '系统支出账户';
      case AccountSide.equity:
        return '系统权益账户';
      case AccountSide.asset:
      case AccountSide.liability:
        // Defensive: the seeder never reaches this branch because
        // [systemAccountCategories] excludes asset / liability.
        throw ArgumentError.value(
          category,
          'category',
          'systemAccountDisplayName is only defined for income / expense / '
              'equity',
        );
    }
  }
}
