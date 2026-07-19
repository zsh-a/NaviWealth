import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:uuid/uuid.dart';

import '../domain/financial_inbox.dart';

class FinancialSignalRepository {
  FinancialSignalRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _uuid = uuid;

  static const _tableName = 'financial_signals';
  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  Future<List<FinancialInboxItem>> reconcile(
    List<FinancialSignalCandidate> candidates, {
    required DateTime now,
  }) async {
    for (final candidate in candidates) {
      await _detect(candidate, now: now);
    }
    await _resolveMissing(
      candidates.map((candidate) => candidate.sourceKey).toSet(),
      now: now,
    );
    return listVisible(now: now);
  }

  Future<void> _resolveMissing(
    Set<String> activeSourceKeys, {
    required DateTime now,
  }) async {
    final owner = await _stamper.currentUserId();
    final rows =
        await (_db.select(_db.financialSignals)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.deletedAt.isNull() &
                  table.status.isNotValue(FinancialSignalStatus.resolved.name),
            ))
            .get();
    for (final row in rows) {
      if (!activeSourceKeys.contains(row.sourceKey)) {
        await _setStatus(row.id, FinancialSignalStatus.resolved, now: now);
      }
    }
  }

  Future<List<FinancialInboxItem>> listVisible({required DateTime now}) async {
    final owner = await _stamper.currentUserId();
    final rows =
        await (_db.select(_db.financialSignals)
              ..where(
                (table) =>
                    table.ownerUserId.equals(owner) & table.deletedAt.isNull(),
              )
              ..where(
                (table) =>
                    table.status.equals(FinancialSignalStatus.open.name) |
                    (table.status.equals(FinancialSignalStatus.snoozed.name) &
                        table.snoozedUntil.isSmallerOrEqualValue(now)),
              )
              ..orderBy([
                (table) => OrderingTerm(
                  expression: table.lastDetectedAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> resolve(String id, {required DateTime now}) =>
      _setStatus(id, FinancialSignalStatus.resolved, now: now);

  Future<void> snooze(
    String id, {
    required DateTime until,
    required DateTime now,
  }) => _setStatus(
    id,
    FinancialSignalStatus.snoozed,
    now: now,
    snoozedUntil: until,
  );

  Future<void> _detect(
    FinancialSignalCandidate candidate, {
    required DateTime now,
  }) async {
    final owner = await _stamper.currentUserId();
    final existing =
        await (_db.select(_db.financialSignals)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.sourceKey.equals(candidate.sourceKey),
            ))
            .getSingleOrNull();
    final evidence = jsonEncode({
      ...candidate.evidence,
      'count': candidate.count,
    });
    final fingerprint = evidence;
    if (existing != null && existing.fingerprint == fingerprint) return;
    final stamp = await _stamper.stamp();
    final id = existing?.id ?? _uuid.v4();
    final companion = FinancialSignalsCompanion.insert(
      id: id,
      kind: candidate.kind.name,
      sourceKey: candidate.sourceKey,
      fingerprint: fingerprint,
      priority: candidate.priority.name,
      evidenceJson: Value(evidence),
      route: candidate.route,
      firstDetectedAt: existing?.firstDetectedAt ?? now,
      lastDetectedAt: now,
      ownerUserId: owner,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      status: const Value('open'),
      snoozedUntil: const Value(null),
      resolvedAt: const Value(null),
    );
    await _db.transaction(() async {
      await _db.into(_db.financialSignals).insertOnConflictUpdate(companion);
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
  }

  Future<void> _setStatus(
    String id,
    FinancialSignalStatus status, {
    required DateTime now,
    DateTime? snoozedUntil,
  }) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(_db.financialSignals)..where(
            (table) =>
                table.id.equals(id) &
                table.ownerUserId.equals(stamp.ownerUserId),
          ))
          .write(
            FinancialSignalsCompanion(
              status: Value(status.name),
              snoozedUntil: Value(snoozedUntil),
              resolvedAt: Value(
                status == FinancialSignalStatus.resolved ? now : null,
              ),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
  }

  FinancialInboxItem _fromRow(FinancialSignalRow row) {
    final evidence = Map<String, Object?>.from(
      jsonDecode(row.evidenceJson) as Map,
    );
    return FinancialInboxItem(
      id: row.id,
      sourceKey: row.sourceKey,
      kind: FinancialInboxKind.values.byName(row.kind),
      priority: FinancialInboxPriority.values.byName(row.priority),
      count: (evidence['count'] as num?)?.toInt() ?? 1,
      route: row.route,
    );
  }
}
