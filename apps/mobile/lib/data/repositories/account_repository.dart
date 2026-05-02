import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../core/sync/op.dart';
import '../../core/sync/op_outbox.dart';
import '../audit/event_log_writer.dart';
import '../db/app_database.dart';
import '../domain/account.dart';
import '../domain/enums.dart';
import '../domain/hlc.dart';
import '../domain/sync_meta.dart';
import 'mutation_context.dart';

/// Read/write API for [Account] rows.
///
/// Every mutation lives in a Drift transaction that *both* writes the row
/// and enqueues a corresponding [Op] into the sync outbox. The two writes
/// committing together is what makes the local store the durable source of
/// queued ops — if the process crashes between them, the row is rolled back
/// and the user sees the failure rather than a silently un-synced change.
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
  Stream<List<Account>> watchActive() {
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
    required AccountType type,
    required String name,
    required String currency,
    String? institution,
    String? accountNumber,
    String? note,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final companion = AccountsCompanion.insert(
      id: id,
      type: type,
      name: name,
      currency: currency,
      institution: Value(institution),
      accountNumber: Value(accountNumber),
      note: Value(note),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    final fields = _accountInsertFields(
      id: id,
      type: type,
      name: name,
      currency: currency,
      institution: institution,
      accountNumber: accountNumber,
      note: note,
      archived: false,
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );

    await _db.transaction(() async {
      await _db.into(_db.accounts).insert(companion);
      await _enqueue(
        opType: OpType.insert,
        rowId: id,
        fields: fields,
        stamp: stamp,
      );
      await _eventLog.recordCreated(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        after: <String, Object?>{
          'type': type.name,
          'name': name,
          'currency': currency,
          'institution': institution,
          'account_number': accountNumber,
          'note': note,
          'archived': false,
        },
      );
    });
    return (await findById(id))!;
  }

  /// Updates only the named fields. Returns the refreshed [Account].
  ///
  /// Sync semantics: the queued op carries `fields_diff` for *just* the
  /// edited columns plus the new sync metadata, so peers apply field-level
  /// LWW per the protocol (`docs/sync-protocol.md` §6).
  Future<Account> update(
    String id, {
    String? name,
    String? currency,
    String? institution,
    bool? clearInstitution,
    String? accountNumber,
    bool? clearAccountNumber,
    String? note,
    bool? clearNote,
    bool? archived,
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
      await _enqueue(
        opType: OpType.update,
        rowId: id,
        fields: diff,
        stamp: stamp,
      );
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
      await _enqueue(
        opType: OpType.delete,
        rowId: id,
        fields: null,
        stamp: stamp,
      );
      await _eventLog.recordSoftDeleted(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        reason: reason,
      );
    });
  }

  // ---------- Helpers ----------

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

  Map<String, Object?> _accountInsertFields({
    required String id,
    required AccountType type,
    required String name,
    required String currency,
    required String? institution,
    required String? accountNumber,
    required String? note,
    required bool archived,
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
  }) {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      'currency': currency,
      'institution': institution,
      'account_number': accountNumber,
      'note': note,
      'archived': archived,
      'owner_user_id': ownerUserId,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'updated_by_device': updatedByDevice,
      'hlc': hlc.toString(),
    };
  }

  Account _toAccount(AccountRow row) {
    return Account(
      id: row.id,
      type: row.type,
      name: row.name,
      currency: row.currency,
      institution: row.institution,
      accountNumber: row.accountNumber,
      note: row.note,
      archived: row.archived,
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
