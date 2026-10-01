import '../../../core/sync/sync_meta.dart';

enum HealthEventTag {
  caffeine,
  lateMeal,
  alcohol,
  illness,
  travel,
  hardWorkout,
  meditation,
  lateScreen,
}

extension HealthEventTagWire on HealthEventTag {
  String get wire => switch (this) {
    HealthEventTag.lateMeal => 'late_meal',
    HealthEventTag.hardWorkout => 'hard_workout',
    HealthEventTag.lateScreen => 'late_screen',
    _ => name,
  };
}

class HealthCheckIn {
  const HealthCheckIn({
    required this.id,
    required this.day,
    required this.sync,
    this.energy,
    this.sleepQuality,
    this.stress,
    this.tags = const [],
    this.note,
  });

  final String id;
  final DateTime day;

  /// All three subjective scales run from 1 (low) to 5 (high).
  final int? energy;
  final int? sleepQuality;
  final int? stress;

  /// Preserve unknown tags received from newer clients when editing a record.
  final List<String> tags;
  final String? note;
  final SyncMeta sync;
}
