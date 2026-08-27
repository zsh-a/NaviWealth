import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String kGarminSyncStatusKeyPrefix = 'lifeos.health.garmin_sync.status.v2';

class GarminSyncStatus {
  const GarminSyncStatus({
    required this.lastAttemptAt,
    required this.lastSuccessAt,
    required this.totalMetrics,
    this.errorCode,
  });

  final DateTime lastAttemptAt;
  final DateTime? lastSuccessAt;
  final int totalMetrics;
  final String? errorCode;

  factory GarminSyncStatus.fromJson(Map<String, Object?> json) {
    return GarminSyncStatus(
      lastAttemptAt: DateTime.parse(json['last_attempt_at']! as String).toUtc(),
      lastSuccessAt: switch (json['last_success_at']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
      totalMetrics: json['total_metrics']! as int,
      errorCode: json['error_code'] as String?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'last_attempt_at': lastAttemptAt.toUtc().toIso8601String(),
    'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
    'total_metrics': totalMetrics,
    'error_code': errorCode,
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
    DateTime? lastSuccessAt,
    required int totalMetrics,
    String? errorCode,
  }) {
    return _preferences.setString(
      _key(ownerUserId),
      jsonEncode(
        GarminSyncStatus(
          lastAttemptAt: lastAttemptAt,
          lastSuccessAt: lastSuccessAt,
          totalMetrics: totalMetrics,
          errorCode: errorCode,
        ).toJson(),
      ),
    );
  }

  Future<void> clear(String ownerUserId) =>
      _preferences.remove(_key(ownerUserId));
}
