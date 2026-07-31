import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String kHealthSyncStatusKey = 'lifeos.health.platform_sync.status.v1';

class HealthSyncStatus {
  const HealthSyncStatus({
    required this.attemptedAt,
    required this.completedAt,
    required this.ok,
    required this.totalFetched,
    required this.upserted,
    required this.unchanged,
    this.lastSuccessAt,
    this.errorCode,
  });

  final DateTime attemptedAt;
  final DateTime completedAt;
  final bool ok;
  final int totalFetched;
  final int upserted;
  final int unchanged;
  final DateTime? lastSuccessAt;
  final String? errorCode;

  factory HealthSyncStatus.fromJson(Map<String, Object?> json) {
    return HealthSyncStatus(
      attemptedAt: DateTime.parse(json['attempted_at']! as String).toUtc(),
      completedAt: DateTime.parse(json['completed_at']! as String).toUtc(),
      ok: json['ok']! as bool,
      totalFetched: json['total_fetched']! as int,
      upserted: json['upserted']! as int,
      unchanged: json['unchanged']! as int,
      lastSuccessAt: switch (json['last_success_at']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
      errorCode: json['error_code'] as String?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'attempted_at': attemptedAt.toUtc().toIso8601String(),
    'completed_at': completedAt.toUtc().toIso8601String(),
    'ok': ok,
    'total_fetched': totalFetched,
    'upserted': upserted,
    'unchanged': unchanged,
    'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
    'error_code': errorCode,
  };
}

class HealthSyncStatusStore {
  const HealthSyncStatusStore(this._preferences);

  final SharedPreferences _preferences;

  HealthSyncStatus? read() {
    final encoded = _preferences.getString(kHealthSyncStatusKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?>) return null;
      return HealthSyncStatus.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> write({
    required DateTime attemptedAt,
    required DateTime completedAt,
    required bool ok,
    required int totalFetched,
    required int upserted,
    required int unchanged,
    String? errorCode,
  }) {
    final previous = read();
    return _preferences.setString(
      kHealthSyncStatusKey,
      jsonEncode(
        HealthSyncStatus(
          attemptedAt: attemptedAt,
          completedAt: completedAt,
          ok: ok,
          totalFetched: totalFetched,
          upserted: upserted,
          unchanged: unchanged,
          lastSuccessAt: ok ? completedAt : previous?.lastSuccessAt,
          errorCode: errorCode,
        ).toJson(),
      ),
    );
  }
}
