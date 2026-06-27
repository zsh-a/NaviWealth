import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/audit/event_log_writer.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:uuid/uuid.dart';

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

  // ---------- Tree queries ----------

  /// Live children of [parentId]. Pass `null` to fetch the top-level set
  /// (Beancount-style root nodes whose `parent_id` is NULL).
  ///
  /// Excludes archived / soft-deleted; *includes* system accounts because
  /// the picker needs them. Sorted by name for stable display order.
  Stream<List<Account>> watchChildrenOf(String? parentId) {
    final query = _db.select(_db.accounts)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.archived.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (parentId == null) {
      query.where((t) => t.parentId.isNull());
    } else {
      query.where((t) => t.parentId.equals(parentId));
    }
    return query.watch().map((rows) => rows.map(_toAccount).toList());
  }

  /// One-shot variant of [watchChildrenOf]. Same filters and ordering.
  Future<List<Account>> accountsByParent(String? parentId) async {
    final query = _db.select(_db.accounts)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.archived.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (parentId == null) {
      query.where((t) => t.parentId.isNull());
    } else {
      query.where((t) => t.parentId.equals(parentId));
    }
    final rows = await query.get();
    return rows.map(_toAccount).toList();
  }

  /// Depth-first walk through the subtree rooted at [rootId]. The root
  /// itself comes first, followed by descendants in name-sorted DFS
  /// order. Returns an empty list when the root doesn't exist or has
  /// been soft-deleted.
  ///
  /// Implementation: BFS by levels via repeated [accountsByParent]
  /// queries — fine for the seeded tree (≤ 4 levels, ≤ 20 nodes) and
  /// keeps us out of recursive-CTE territory. Larger user-built trees
  /// will still be linear in the row count.
  Future<List<Account>> walkSubtree(String rootId) async {
    final root = await findById(rootId);
    if (root == null || root.archived || root.sync.deletedAt != null) {
      return const [];
    }
    final out = <Account>[root];
    final stack = <Account>[root];
    while (stack.isNotEmpty) {
      final parent = stack.removeLast();
      final children = await accountsByParent(parent.id);
      for (final c in children.reversed) {
        out.add(c);
        stack.add(c);
      }
    }
    return out;
  }

  /// Returns the chain from the tree root down to [accountId], inclusive
  /// of both. Returns an empty list if [accountId] doesn't exist.
  ///
  /// Defensive against malformed parent links: stops walking after
  /// 64 hops to prevent an accidental cycle from spinning forever.
  Future<List<Account>> pathOf(String accountId) async {
    final out = <Account>[];
    var cursor = await findById(accountId);
    var hops = 0;
    while (cursor != null && hops < 64) {
      out.add(cursor);
      final parentId = cursor.parentId;
      if (parentId == null) break;
      cursor = await findById(parentId);
      hops++;
    }
    return out.reversed.toList();
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

  /// Idempotently seeds the default Beancount-style account tree the
  /// double-entry posting model leans on:
  ///
  /// ```
  /// Income/{Salary,Dividend,Interest,CapitalGains,Other}
  /// Expenses/{Dining,Groceries,Coffee,Transport,RideHailing,Housing,Utilities,
  /// Household,Shopping,Subscriptions,Entertainment,Medical,Fitness,Education,
  /// Travel,Communication,FamilySupport,Gift,Pets,Trading/{Fee,Tax,Interest},
  /// Tax/{Withholding},Other}
  /// Equity/{OpeningBalance,Splits,Adjustments}
  /// ```
  ///
  /// Three roots (carrying the existing ids) plus a curated set of
  /// common leaves for a total of 37 seeded accounts on a fresh install.
  ///
  /// Each row uses a deterministic id derived from
  /// [systemAccountIdForPath], so re-running the seed is a free no-op
  /// and a sync-borne replay never duplicates a row. Returns the number
  /// of rows actually inserted on this call (0 on a re-seed). The seed
  /// list is iterated in parent-before-child order; the seeder still
  /// resolves a missing parent gracefully because the parent / child
  /// relationship has no SQL FK.
  ///
  /// [currency] picks the carrier currency for the seeded rows. The
  /// dashboard converts everything through FX, so the currency choice is
  /// largely cosmetic — defaulting to `CNY` matches the app's primary
  /// locale and keeps system rows out of the FX-mismatch banner on
  /// fresh installs that haven't yet pulled an FX rate table.
  Future<int> seedSystemAccounts({String currency = 'CNY'}) async {
    final ownerUserId = await _stamper.currentUserId();
    var inserted = 0;
    for (final seed in _kSystemAccountTreeSeeds) {
      final id = systemAccountIdForPath(seed.path, ownerUserId: ownerUserId);
      final existing = await (_db.select(
        _db.accounts,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing != null) continue;

      final stamp = await _stamper.stamp();
      const type = AccountCategory.asset;
      final name = seed.isRoot
          ? systemAccountDisplayName(seed.category)
          : seed.name;
      final parentId = seed.parentPath == null
          ? null
          : systemAccountIdForPath(seed.parentPath!, ownerUserId: ownerUserId);
      final companion = AccountsCompanion.insert(
        id: id,
        type: type,
        name: name,
        currency: currency,
        category: Value(seed.category),
        parentId: Value(parentId),
        icon: Value(seed.icon),
        color: Value(seed.color),
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      );
      await _db.transaction(() async {
        await _db.into(_db.accounts).insert(companion);
        await _outbox.enqueue(table: _tableName, rowId: id);
        // Mirror the audit shape `create` uses so an account-history view
        // can replay system-account seeding the same way it replays user
        // account creates.
        await _eventLog.recordCreated(
          entityTable: _tableName,
          entityId: id,
          stamp: stamp,
          after: <String, Object?>{
            'type': type.name,
            'name': name,
            'currency': currency,
            'category': seed.category.name,
            'institution': null,
            'account_number': null,
            'note': null,
            'archived': false,
            'parent_id': parentId,
            'icon': seed.icon,
            'color': seed.color,
          },
        );
      });
      inserted++;
    }
    return inserted;
  }
}

/// Specification for one seeded system account. Static const so the seed
/// is the single source of truth for the default tree shape, picker
/// defaults and the Beancount export naming convention.
class _SystemAccountSeed {
  const _SystemAccountSeed({
    required this.path,
    required this.parentPath,
    required this.name,
    required this.category,
    required this.icon,
    required this.color,
  });

  /// Stable path under the user's prefix, e.g. `income`,
  /// `expense:trading`, `expense:trading:fee`. The full id is
  /// `system-account:<userId>:<path>`.
  final String path;

  /// Parent path, or `null` on the three roots. Always one segment
  /// shorter than [path] when set.
  final String? parentPath;

  /// English Beancount-canonical name (e.g. `Salary`, `Trading Fee`).
  /// Roots ignore this and use the localised display name instead.
  final String name;

  final AccountSide category;

  /// Material icon name (e.g. `work`, `restaurant`).
  final String icon;

  /// Hex color used for the avatar tint. Picked per-category so all
  /// income leaves share a green family, expenses red, equity blue.
  final String color;

  bool get isRoot => parentPath == null;
}

/// Default account tree seeded on a fresh install. Iterated in parent-
/// before-child order so [AccountRepository.seedSystemAccounts] can rely
/// on the parent already existing for the audit-log capture (the SQL
/// layer doesn't enforce a foreign key, so this is a soft contract).
const List<_SystemAccountSeed> _kSystemAccountTreeSeeds = [
  // ---- Roots ----
  _SystemAccountSeed(
    path: 'income',
    parentPath: null,
    name: 'Income',
    category: AccountSide.income,
    icon: 'south_west',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'expense',
    parentPath: null,
    name: 'Expenses',
    category: AccountSide.expense,
    icon: 'north_east',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'equity',
    parentPath: null,
    name: 'Equity',
    category: AccountSide.equity,
    icon: 'account_balance',
    color: '#3B82F6',
  ),

  // ---- Income leaves ----
  _SystemAccountSeed(
    path: 'income:salary',
    parentPath: 'income',
    name: 'Salary',
    category: AccountSide.income,
    icon: 'work',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'income:dividend',
    parentPath: 'income',
    name: 'Dividend',
    category: AccountSide.income,
    icon: 'paid',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'income:interest',
    parentPath: 'income',
    name: 'Interest',
    category: AccountSide.income,
    icon: 'savings',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'income:capitalGains',
    parentPath: 'income',
    name: 'Capital Gains',
    category: AccountSide.income,
    icon: 'trending_up',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'income:options',
    parentPath: 'income',
    name: 'Options Income',
    category: AccountSide.income,
    icon: 'show_chart',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'income:other',
    parentPath: 'income',
    name: 'Other Income',
    category: AccountSide.income,
    icon: 'more_horiz',
    color: '#10B981',
  ),

  // ---- Everyday expense leaves + Trading / Tax branches ----
  _SystemAccountSeed(
    path: 'expense:dining',
    parentPath: 'expense',
    name: 'Dining',
    category: AccountSide.expense,
    icon: 'restaurant',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:groceries',
    parentPath: 'expense',
    name: 'Groceries',
    category: AccountSide.expense,
    icon: 'local_grocery_store',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:coffee',
    parentPath: 'expense',
    name: 'Coffee',
    category: AccountSide.expense,
    icon: 'local_cafe',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:transport',
    parentPath: 'expense',
    name: 'Transport',
    category: AccountSide.expense,
    icon: 'directions_bus',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:rideHailing',
    parentPath: 'expense',
    name: 'Ride Hailing',
    category: AccountSide.expense,
    icon: 'local_taxi',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:housing',
    parentPath: 'expense',
    name: 'Housing',
    category: AccountSide.expense,
    icon: 'home',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:utilities',
    parentPath: 'expense',
    name: 'Utilities',
    category: AccountSide.expense,
    icon: 'bolt',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:household',
    parentPath: 'expense',
    name: 'Household',
    category: AccountSide.expense,
    icon: 'chair',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:shopping',
    parentPath: 'expense',
    name: 'Shopping',
    category: AccountSide.expense,
    icon: 'shopping_bag',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:subscriptions',
    parentPath: 'expense',
    name: 'Subscriptions',
    category: AccountSide.expense,
    icon: 'credit_card',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:entertainment',
    parentPath: 'expense',
    name: 'Entertainment',
    category: AccountSide.expense,
    icon: 'sports_esports',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:medical',
    parentPath: 'expense',
    name: 'Medical',
    category: AccountSide.expense,
    icon: 'medical_services',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:fitness',
    parentPath: 'expense',
    name: 'Fitness',
    category: AccountSide.expense,
    icon: 'fitness_center',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:education',
    parentPath: 'expense',
    name: 'Education',
    category: AccountSide.expense,
    icon: 'school',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:travel',
    parentPath: 'expense',
    name: 'Travel',
    category: AccountSide.expense,
    icon: 'flight',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:communication',
    parentPath: 'expense',
    name: 'Communication',
    category: AccountSide.expense,
    icon: 'smartphone',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:gift',
    parentPath: 'expense',
    name: 'Gift',
    category: AccountSide.expense,
    icon: 'card_giftcard',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:familySupport',
    parentPath: 'expense',
    name: 'Family Support',
    category: AccountSide.expense,
    icon: 'redeem',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:pets',
    parentPath: 'expense',
    name: 'Pets',
    category: AccountSide.expense,
    icon: 'pets',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:trading',
    parentPath: 'expense',
    name: 'Trading',
    category: AccountSide.expense,
    icon: 'show_chart',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:trading:fee',
    parentPath: 'expense:trading',
    name: 'Trading Fee',
    category: AccountSide.expense,
    icon: 'receipt_long',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:trading:tax',
    parentPath: 'expense:trading',
    name: 'Trading Tax',
    category: AccountSide.expense,
    icon: 'request_quote',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:trading:interest',
    parentPath: 'expense:trading',
    name: 'Trading Interest',
    category: AccountSide.expense,
    icon: 'credit_card',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:tax',
    parentPath: 'expense',
    name: 'Tax',
    category: AccountSide.expense,
    icon: 'request_quote',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:tax:withholding',
    parentPath: 'expense:tax',
    name: 'Withholding Tax',
    category: AccountSide.expense,
    icon: 'request_quote',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'expense:other',
    parentPath: 'expense',
    name: 'Other Expense',
    category: AccountSide.expense,
    icon: 'more_horiz',
    color: '#EF4444',
  ),

  // ---- Equity leaves ----
  _SystemAccountSeed(
    path: 'equity:openingBalance',
    parentPath: 'equity',
    name: 'Opening Balance',
    category: AccountSide.equity,
    icon: 'flag',
    color: '#3B82F6',
  ),
  _SystemAccountSeed(
    path: 'equity:splits',
    parentPath: 'equity',
    name: 'Stock Splits',
    category: AccountSide.equity,
    icon: 'call_split',
    color: '#3B82F6',
  ),
  _SystemAccountSeed(
    path: 'equity:adjustments',
    parentPath: 'equity',
    name: 'Adjustments',
    category: AccountSide.equity,
    icon: 'tune',
    color: '#3B82F6',
  ),
];
