import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../core/sync/sync_meta.dart';
import '../domain/health_check_in.dart';
import 'health_series.dart';

class HealthCheckInRepository {
  HealthCheckInRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    DateTime Function()? clock,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final DateTime Function() _clock;
  static const table = 'health_check_ins';

  Stream<List<HealthCheckIn>> watchInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) {
    final query = _db.select(_db.healthCheckIns)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.day.isBiggerOrEqualValue(healthDay(from)))
      ..where((t) => t.day.isSmallerThanValue(healthDay(to)))
      ..orderBy([
        (t) => OrderingTerm.desc(t.updatedAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return query.watch().map((rows) {
      // Owner migration can leave an older id for the same date. Pick the
      // latest state before filtering tombstones so deletion cannot revive it.
      final days = <DateTime, HealthCheckInRow>{};
      for (final row in rows) {
        final day = row.day.toUtc();
        final previous = days[day];
        if (previous == null || _compareState(row, previous) > 0) {
          days[day] = row;
        }
      }
      final entries =
          days.values
              .where((row) => row.deletedAt == null)
              .map(_fromRow)
              .toList()
            ..sort((a, b) => b.day.compareTo(a.day));
      return List<HealthCheckIn>.unmodifiable(entries);
    });
  }

  Future<HealthCheckIn?> findDay({
    required String ownerUserId,
    required DateTime day,
  }) async {
    final row = await _findRow(ownerUserId, healthDay(day));
    return row == null || row.deletedAt != null ? null : _fromRow(row);
  }

  Future<HealthCheckIn> save({
    required DateTime day,
    int? energy,
    int? sleepQuality,
    int? stress,
    List<String> tags = const [],
    String? note,
    String? expectedOwnerUserId,
  }) async {
    final date = healthDay(day);
    if (date.isAfter(healthDay(_clock())) || date.year < 1970) {
      throw ArgumentError.value(
        day,
        'day',
        'Check-ins need a past or current date.',
      );
    }
    for (final value in [energy, sleepQuality, stress]) {
      if (value != null && (value < 1 || value > 5)) {
        throw ArgumentError.value(
          value,
          'score',
          'Expected a value from 1 to 5.',
        );
      }
    }
    final cleanNote = note?.trim();
    final cleanTags =
        tags
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if ((cleanNote?.length ?? 0) > 1000 ||
        cleanTags.length > 32 ||
        cleanTags.any((tag) => tag.length > 64)) {
      throw ArgumentError('Check-in content exceeds the supported length.');
    }
    if (energy == null &&
        sleepQuality == null &&
        stress == null &&
        cleanTags.isEmpty &&
        (cleanNote?.isEmpty ?? true)) {
      throw ArgumentError('Record at least one feeling, event, or note.');
    }
    final stamp = await _stamper.stamp();
    if (expectedOwnerUserId != null &&
        stamp.ownerUserId != expectedOwnerUserId) {
      throw StateError('The active user changed. Reopen the check-in.');
    }
    return _db.transaction(() async {
      final existing = await _findRow(stamp.ownerUserId, date);
      final id =
          existing?.id ??
          'check-in:${Uri.encodeComponent(stamp.ownerUserId)}:${date.toIso8601String().substring(0, 10)}';
      final entry = HealthCheckIn(
        id: id,
        day: date,
        energy: energy,
        sleepQuality: sleepQuality,
        stress: stress,
        tags: List.unmodifiable(cleanTags),
        note: cleanNote == null || cleanNote.isEmpty ? null : cleanNote,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await _db
          .into(_db.healthCheckIns)
          .insert(
            HealthCheckInsCompanion.insert(
              id: entry.id,
              day: entry.day,
              energy: Value(entry.energy),
              sleepQuality: Value(entry.sleepQuality),
              stress: Value(entry.stress),
              tagsJson: Value(jsonEncode(entry.tags)),
              note: Value(entry.note),
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
            mode: InsertMode.insertOrReplace,
          );
      await _outbox.enqueue(table: table, rowId: id);
      return entry;
    });
  }

  Future<void> delete(HealthCheckIn entry) async {
    final stamp = await _stamper.stamp();
    if (stamp.ownerUserId != entry.sync.ownerUserId) {
      throw StateError('Check-in belongs to another user.');
    }
    await _db.transaction(() async {
      final count =
          await (_db.update(_db.healthCheckIns)..where(
                (t) =>
                    t.id.equals(entry.id) &
                    t.ownerUserId.equals(stamp.ownerUserId),
              ))
              .write(
                HealthCheckInsCompanion(
                  deletedAt: Value(stamp.now),
                  updatedAt: Value(stamp.now),
                  updatedByDevice: Value(stamp.deviceId),
                  hlc: Value(stamp.hlc),
                ),
              );
      if (count != 1) throw StateError('Check-in no longer exists.');
      await _outbox.enqueue(table: table, rowId: entry.id);
    });
  }

  Future<HealthCheckInRow?> _findRow(String owner, DateTime day) async {
    final rows = await (_db.select(
      _db.healthCheckIns,
    )..where((t) => t.ownerUserId.equals(owner) & t.day.equals(day))).get();
    if (rows.isEmpty) return null;
    return rows.reduce((a, b) => _compareState(a, b) > 0 ? a : b);
  }

  static int _compareState(HealthCheckInRow a, HealthCheckInRow b) {
    final version = a.hlc.compareTo(b.hlc);
    return version == 0 ? a.id.compareTo(b.id) : version;
  }

  HealthCheckIn _fromRow(HealthCheckInRow row) {
    List<String> tags = const [];
    try {
      final decoded = jsonDecode(row.tagsJson);
      if (decoded is List) tags = decoded.whereType<String>().toList();
    } on FormatException {
      /* Optional metadata must not hide a saved check-in. */
    }
    return HealthCheckIn(
      id: row.id,
      day: row.day.toUtc(),
      energy: row.energy,
      sleepQuality: row.sleepQuality,
      stress: row.stress,
      tags: List.unmodifiable(tags),
      note: row.note,
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
