import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String kGarminSyncStatusKeyPrefix = 'lifeos.health.garmin_sync.status.v2';

class GarminSyncStatus {
  const GarminSyncStatus({
    required this.lastAttemptAt,
    required this.lastSuccessAt,
    required this.totalMetrics,
  });

  final DateTime lastAttemptAt;
  final DateTime lastSuccessAt;
  final int totalMetrics;

  factory GarminSyncStatus.fromJson(Map<String, Object?> json) {
    return GarminSyncStatus(
      lastAttemptAt: DateTime.parse(json['last_attempt_at']! as String).toUtc(),
      lastSuccessAt: DateTime.parse(json['last_success_at']! as String).toUtc(),
      totalMetrics: json['total_metrics']! as int,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'last_attempt_at': lastAttemptAt.toUtc().toIso8601String(),
    'last_success_at': lastSuccessAt.toUtc().toIso8601String(),
    'total_metrics': totalMetrics,
  };
}

class GarminSyncStatusStore {
  const GarminSyncStatusStore(this._preferences);

  final SharedPreferences _preferences;

  String _key(String ownerUserId) => '$kGarminSyncStatusKeyPrefix.$ownerUserId';

  GarminSyncStatus? read(String ownerUserId) {
    final encoded = _preferences.getString(_key(ownerUserId));
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?>) return null;
      return GarminSyncStatus.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> write({
    required String ownerUserId,
    required DateTime lastAttemptAt,
    required DateTime lastSuccessAt,
    required int totalMetrics,
  }) {
    return _preferences.setString(
      _key(ownerUserId),
      jsonEncode(
        GarminSyncStatus(
          lastAttemptAt: lastAttemptAt,
          lastSuccessAt: lastSuccessAt,
          totalMetrics: totalMetrics,
        ).toJson(),
      ),
    );
  }

  Future<void> clear(String ownerUserId) =>
      _preferences.remove(_key(ownerUserId));
}
