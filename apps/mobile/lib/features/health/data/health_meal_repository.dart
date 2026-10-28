import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../core/sync/sync_meta.dart';
import '../domain/health_meal.dart';
import 'health_series.dart';

class HealthMealRepository {
  HealthMealRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    DateTime Function()? clock,
    bool Function(String owner)? writesAllowed,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _clock = clock ?? DateTime.now,
       _writesAllowed = writesAllowed ?? ((_) => true);

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final DateTime Function() _clock;
  final bool Function(String owner) _writesAllowed;
  static const table = 'health_meals';
  static const maxPhotoBytes = 2 * 1024 * 1024;

  Stream<List<HealthMeal>> watchInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) {
    final query = _db.select(_db.healthMeals)
      ..where(
        (t) =>
            t.ownerUserId.equals(ownerUserId) &
            t.deletedAt.isNull() &
            t.day.isBiggerOrEqualValue(healthDay(from)) &
            t.day.isSmallerThanValue(healthDay(to)),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.capturedAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return query.watch().map(
      (rows) => rows.map(_fromRow).toList(growable: false),
    );
  }

  Future<HealthMeal?> find({
    required String id,
    required String ownerUserId,
  }) async {
    final row =
        await (_db.select(_db.healthMeals)..where(
              (t) =>
                  t.id.equals(id) &
                  t.ownerUserId.equals(ownerUserId) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<Uint8List?> photo({
    required String id,
    required String ownerUserId,
  }) async {
    // Require a live parent, so a tombstone received from Sync also hides its
    // device-local image without having to add domain callbacks to RowApplier.
    if (await find(id: id, ownerUserId: ownerUserId) == null) return null;
    final row =
        await (_db.select(_db.healthMealPhotos)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row?.bytes;
  }

  Future<HealthMeal> save({
    String? id,
    required String expectedOwnerUserId,
    Hlc? expectedRevision,
    required DateTime capturedAt,
    required DateTime day,
    required HealthMealType type,
    required List<MealFood> foods,
    String? note,
    String? recognitionModel,
    Uint8List? photoBytes,
    bool removePhoto = false,
  }) async {
    _requireEnabled(expectedOwnerUserId);
    final date = healthDay(day);
    if (date.year < 1970 ||
        date.isAfter(healthDay(_clock())) ||
        capturedAt.isAfter(_clock().add(const Duration(minutes: 1))) ||
        capturedAt.year < 1970 ||
        foods.isEmpty ||
        foods.length > 30 ||
        foods.any((food) => !food.isValid) ||
        (note?.length ?? 0) > 1000 ||
        (recognitionModel?.length ?? 0) > 200 ||
        (photoBytes != null &&
            (photoBytes.isEmpty || photoBytes.length > maxPhotoBytes))) {
      throw ArgumentError('Invalid meal, date, nutrient values, or photo size');
    }
    final stamp = await _stamper.stamp();
    if (stamp.ownerUserId != expectedOwnerUserId) {
      throw StateError('The active user changed. Reopen the meal.');
    }
    final mealId = id ?? const Uuid().v4();
    return _db.transaction(() async {
      _requireEnabled(stamp.ownerUserId);
      final previous = await (_db.select(
        _db.healthMeals,
      )..where((t) => t.id.equals(mealId))).getSingleOrNull();
      if (previous != null &&
          (previous.ownerUserId != stamp.ownerUserId ||
              previous.deletedAt != null ||
              previous.hlc != expectedRevision)) {
        throw StateError('The meal changed. Reopen it before editing.');
      }
      if (previous == null && expectedRevision != null) {
        throw StateError('The meal no longer exists.');
      }
      _requireEnabled(stamp.ownerUserId);
      final meal = HealthMeal(
        id: mealId,
        capturedAt: capturedAt.toUtc(),
        day: date,
        type: type,
        foods: foods,
        note: _optional(note),
        recognitionModel: _optional(recognitionModel),
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await _db
          .into(_db.healthMeals)
          .insertOnConflictUpdate(
            HealthMealsCompanion.insert(
              id: meal.id,
              capturedAt: meal.capturedAt,
              day: meal.day,
              mealType: meal.type.name,
              foodsJson: HealthMeal.encodeFoods(meal.foods),
              note: Value(meal.note),
              recognitionModel: Value(meal.recognitionModel),
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      if (removePhoto) {
        await (_db.delete(_db.healthMealPhotos)..where(
              (t) =>
                  t.id.equals(mealId) & t.ownerUserId.equals(stamp.ownerUserId),
            ))
            .go();
      } else if (photoBytes != null) {
        await _db
            .into(_db.healthMealPhotos)
            .insertOnConflictUpdate(
              HealthMealPhotosCompanion.insert(
                id: mealId,
                ownerUserId: stamp.ownerUserId,
                bytes: photoBytes,
              ),
            );
      }
      await _outbox.enqueue(table: table, rowId: mealId);
      return meal;
    });
  }

  Future<void> delete(HealthMeal meal) async {
    _requireEnabled(meal.sync.ownerUserId);
    final stamp = await _stamper.stamp();
    if (stamp.ownerUserId != meal.sync.ownerUserId) {
      throw StateError('The meal belongs to another user.');
    }
    await _db.transaction(() async {
      _requireEnabled(stamp.ownerUserId);
      final count =
          await (_db.update(_db.healthMeals)..where(
                (t) =>
                    t.id.equals(meal.id) &
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.deletedAt.isNull() &
                    t.hlc.equals(meal.sync.hlc.toString()),
              ))
              .write(
                HealthMealsCompanion(
                  deletedAt: Value(stamp.now),
                  updatedAt: Value(stamp.now),
                  updatedByDevice: Value(stamp.deviceId),
                  hlc: Value(stamp.hlc),
                ),
              );
      if (count != 1) {
        throw StateError('The meal changed. Reopen it before deleting.');
      }
      await (_db.delete(_db.healthMealPhotos)..where(
            (t) =>
                t.id.equals(meal.id) & t.ownerUserId.equals(stamp.ownerUserId),
          ))
          .go();
      await _outbox.enqueue(table: table, rowId: meal.id);
    });
  }

  void _requireEnabled(String owner) {
    if (!_writesAllowed(owner)) {
      throw StateError('The active user or HealthOS setting changed.');
    }
  }

  static String? _optional(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  HealthMeal _fromRow(HealthMealRow row) => HealthMeal(
    id: row.id,
    capturedAt: row.capturedAt.toUtc(),
    day: row.day.toUtc(),
    type: HealthMealType.values.byName(row.mealType),
    foods: HealthMeal.decodeFoods(row.foodsJson),
    note: row.note,
    recognitionModel: row.recognitionModel,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
      deletedAt: row.deletedAt,
    ),
  );
}
