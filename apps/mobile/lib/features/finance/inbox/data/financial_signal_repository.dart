import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/core/lifeos/action_outcome.dart';
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

  /// Upserts a partial detector without resolving signals owned by detectors
  /// that did not run. The lightweight Life hub uses this for import state;
  /// only the full Inbox scan is authoritative enough to call [reconcile].
  Future<List<FinancialInboxItem>> detectAll(
    List<FinancialSignalCandidate> candidates, {
    required DateTime now,
  }) async {
    for (final candidate in candidates) {
      await _detect(candidate, now: now);
    }
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

  Stream<Map<String, ActionOutcomeSummary>> watchActionOutcomes() async* {
    final owner = await _stamper.currentUserId();
    final query = _db.select(_db.financialSignals)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) &
            table.deletedAt.isNull() &
            table.actionId.isNotNull() &
            table.revalidatedAt.isNotNull() &
            table.revalidationStatus.isIn(<String>[
              FinancialSignalRevalidationStatus.cleared.name,
              FinancialSignalRevalidationStatus.stillDetected.name,
            ]),
      );
    yield* query.watch().map(
      (rows) => Map.unmodifiable(<String, ActionOutcomeSummary>{
        for (final row in rows)
          row.actionId!: ActionOutcomeSummary(
            status:
                row.revalidationStatus ==
                    FinancialSignalRevalidationStatus.cleared.name
                ? ActionOutcomeStatus.signalCleared
                : ActionOutcomeStatus.signalStillActive,
            sourceLabel: row.kind,
            sourceCapturedAt: row.firstDetectedAt,
            evaluatedAt: row.revalidatedAt!,
          ),
      }),
    );
  }

  Future<void> resolve(String id, {required DateTime now}) =>
      _setStatus(id, FinancialSignalStatus.resolved, now: now);

  /// Resolve a user-selected group atomically so a failed bulk action never
  /// leaves half the group cleared.
  Future<void> resolveMany(
    Iterable<String> ids, {
    required DateTime now,
  }) async {
    final uniqueIds = ids.toSet();
    if (uniqueIds.isEmpty) return;
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      for (final id in uniqueIds) {
        await (_db.update(_db.financialSignals)..where(
              (table) =>
                  table.id.equals(id) &
                  table.ownerUserId.equals(stamp.ownerUserId),
            ))
            .write(
              FinancialSignalsCompanion(
                status: Value(FinancialSignalStatus.resolved.name),
                snoozedUntil: const Value(null),
                resolvedAt: Value(now),
                updatedAt: Value(stamp.now),
                updatedByDevice: Value(stamp.deviceId),
                hlc: Value(stamp.hlc),
              ),
            );
        await _outbox.enqueue(table: _tableName, rowId: id);
      }
    });
  }

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

  Future<void> linkAction(
    String id, {
    required String actionId,
    required DateTime now,
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
              actionId: Value(actionId),
              revalidationStatus: const Value(null),
              revalidatedAt: const Value(null),
              actionCompletedAt: const Value(null),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
  }

  Future<FinancialSignalRevalidationReport> revalidateClosedActions({
    required List<LifeClosedAction> actions,
    required List<FinancialSignalCandidate>? candidates,
    required DateTime observedAt,
  }) async {
    final relevant = <String, LifeClosedAction>{
      for (final action in actions)
        if (action.sourceRowFamily == 'fin:financial_signals' &&
            action.sourceRowId != null)
          action.id: action,
    };
    if (relevant.isEmpty) return const FinancialSignalRevalidationReport();
    final owner = await _stamper.currentUserId();
    final rows =
        await (_db.select(_db.financialSignals)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.deletedAt.isNull() &
                  table.actionId.isIn(relevant.keys.toList(growable: false)),
            ))
            .get();
    final candidatesByKey = <String, FinancialSignalCandidate>{
      for (final candidate in candidates ?? const <FinancialSignalCandidate>[])
        candidate.sourceKey: candidate,
    };
    var cleared = 0;
    var stillDetected = 0;
    var inconclusive = 0;
    var actionDropped = 0;
    var actionCompleted = 0;
    for (final row in rows) {
      final action = relevant[row.actionId];
      if (action == null || action.sourceRowId != row.id) continue;
      final alreadyEvaluated = row.actionCompletedAt?.isAtSameMomentAs(
        action.completedAt,
      );
      if (alreadyEvaluated == true &&
          row.revalidationStatus !=
              FinancialSignalRevalidationStatus.inconclusive.name) {
        continue;
      }
      if (action.status == LifeClosedActionStatus.dropped) {
        await _writeRevalidation(
          row: row,
          action: action,
          status: FinancialSignalRevalidationStatus.actionDropped,
          observedAt: observedAt,
        );
        actionDropped++;
        continue;
      }
      if (alreadyEvaluated != true) actionCompleted++;
      if (candidates == null) {
        if (alreadyEvaluated == true) continue;
        await _writeRevalidation(
          row: row,
          action: action,
          status: FinancialSignalRevalidationStatus.inconclusive,
          observedAt: observedAt,
        );
        inconclusive++;
        continue;
      }
      final candidate = candidatesByKey[row.sourceKey];
      if (candidate == null) {
        await _writeRevalidation(
          row: row,
          action: action,
          status: FinancialSignalRevalidationStatus.cleared,
          observedAt: observedAt,
        );
        cleared++;
      } else {
        await _detect(candidate, now: observedAt);
        final refreshed = await _findById(row.id, owner);
        if (refreshed == null) continue;
        await _writeRevalidation(
          row: refreshed,
          action: action,
          status: FinancialSignalRevalidationStatus.stillDetected,
          observedAt: observedAt,
        );
        stillDetected++;
      }
    }
    return FinancialSignalRevalidationReport(
      actionCompleted: actionCompleted,
      cleared: cleared,
      stillDetected: stillDetected,
      inconclusive: inconclusive,
      actionDropped: actionDropped,
    );
  }

  Future<FinancialSignalRow?> _findById(String id, String owner) =>
      (_db.select(_db.financialSignals)..where(
            (table) => table.id.equals(id) & table.ownerUserId.equals(owner),
          ))
          .getSingleOrNull();

  Future<void> _writeRevalidation({
    required FinancialSignalRow row,
    required LifeClosedAction action,
    required FinancialSignalRevalidationStatus status,
    required DateTime observedAt,
  }) async {
    final stamp = await _stamper.stamp();
    final statusWrite = switch (status) {
      FinancialSignalRevalidationStatus.cleared => Value(
        FinancialSignalStatus.resolved.name,
      ),
      FinancialSignalRevalidationStatus.stillDetected => Value(
        FinancialSignalStatus.open.name,
      ),
      _ => const Value<String>.absent(),
    };
    final resolvedAtWrite = switch (status) {
      FinancialSignalRevalidationStatus.cleared => Value(observedAt),
      FinancialSignalRevalidationStatus.stillDetected => const Value<DateTime?>(
        null,
      ),
      _ => const Value<DateTime?>.absent(),
    };
    await _db.transaction(() async {
      await (_db.update(_db.financialSignals)..where(
            (table) =>
                table.id.equals(row.id) &
                table.ownerUserId.equals(stamp.ownerUserId) &
                table.actionId.equals(action.id),
          ))
          .write(
            FinancialSignalsCompanion(
              status: statusWrite,
              resolvedAt: resolvedAtWrite,
              revalidationStatus: Value(status.name),
              revalidatedAt: Value(observedAt),
              actionCompletedAt: Value(action.completedAt),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
      await _outbox.enqueue(table: _tableName, rowId: row.id);
    });
  }

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
      actionId: Value(existing?.actionId),
      revalidationStatus: Value(existing?.revalidationStatus),
      revalidatedAt: Value(existing?.revalidatedAt),
      actionCompletedAt: Value(existing?.actionCompletedAt),
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
    final count = (evidence.remove('count') as num?)?.toInt() ?? 1;
    return FinancialInboxItem(
      id: row.id,
      sourceKey: row.sourceKey,
      kind: FinancialInboxKind.values.byName(row.kind),
      priority: FinancialInboxPriority.values.byName(row.priority),
      count: count,
      route: row.route,
      evidence: Map.unmodifiable(evidence),
      firstDetectedAt: row.firstDetectedAt,
      lastDetectedAt: row.lastDetectedAt,
      actionId: row.actionId,
      revalidationStatus: row.revalidationStatus == null
          ? null
          : FinancialSignalRevalidationStatus.values.byName(
              row.revalidationStatus!,
            ),
      revalidatedAt: row.revalidatedAt,
      actionCompletedAt: row.actionCompletedAt,
    );
  }
}
