import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String kGarminSyncStatusKeyPrefix = 'lifeos.health.garmin_sync.status.v2';

class GarminSyncStatus {
  const GarminSyncStatus({
    required this.lastAttemptAt,
    required this.lastSuccessAt,
    required this.totalMetrics,
    this.errorCode,
    this.lastCheckedAt,
    this.nextRetryAt,
    this.unchanged = 0,
    this.partial = false,
    this.failureCount = 0,
  });

  final DateTime lastAttemptAt;
  final DateTime? lastSuccessAt;
  final int totalMetrics;
  final String? errorCode;
  final DateTime? lastCheckedAt;
  final DateTime? nextRetryAt;
  final int unchanged;
  final bool partial;
  final int failureCount;

  factory GarminSyncStatus.fromJson(Map<String, Object?> json) =>
      GarminSyncStatus(
        lastAttemptAt: DateTime.parse(json['last_attempt_at']! as String)
            .toUtc(),
        lastSuccessAt: _date(json['last_success_at']),
        totalMetrics: json['total_metrics']! as int,
        errorCode: json['error_code'] as String?,
        lastCheckedAt: _date(json['last_checked_at']),
        nextRetryAt: _date(json['next_retry_at']),
        unchanged: json['unchanged'] as int? ?? 0,
        partial: json['partial'] == true,
        failureCount: json['failure_count'] as int? ?? 0,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'last_attempt_at': lastAttemptAt.toUtc().toIso8601String(),
    'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
    'total_metrics': totalMetrics,
    'error_code': errorCode,
    'last_checked_at': lastCheckedAt?.toUtc().toIso8601String(),
    'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
    'unchanged': unchanged,
    'partial': partial,
    'failure_count': failureCount,
  };
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

/// Operational state only, never Garmin credentials or business data.
class GarminSyncStatusStore {
  const GarminSyncStatusStore(this._preferences);
  final SharedPreferences _preferences;

  String _key(String owner, String? region) =>
      '$kGarminSyncStatusKeyPrefix.$owner${region == null ? '' : '.$region'}';

  GarminSyncStatus? read(String ownerUserId, {String? region}) {
    final encoded =
        _preferences.getString(_key(ownerUserId, region)) ??
        (region == null
            ? null
            : _preferences.getString(_key(ownerUserId, null)));
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
    String? region,
    required DateTime lastAttemptAt,
    DateTime? lastSuccessAt,
    required int totalMetrics,
    String? errorCode,
    DateTime? lastCheckedAt,
    DateTime? nextRetryAt,
    int unchanged = 0,
    bool partial = false,
    int failureCount = 0,
  }) => _preferences.setString(
    _key(ownerUserId, region),
    jsonEncode(
      GarminSyncStatus(
        lastAttemptAt: lastAttemptAt,
        lastSuccessAt: lastSuccessAt,
        totalMetrics: totalMetrics,
        errorCode: errorCode,
        lastCheckedAt: lastCheckedAt,
        nextRetryAt: nextRetryAt,
        unchanged: unchanged,
        partial: partial,
        failureCount: failureCount,
      ).toJson(),
    ),
  );

  Map<String, DateTime> checkedDays(String owner, String region) {
    final raw = _preferences.getString('${_key(owner, region)}.days');
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (_date(entry.value) case final DateTime date) entry.key: date,
      };
    } on Object {
      return {};
    }
  }

  Future<void> saveCheckedDays(
    String owner,
    String region,
    Map<String, DateTime> days,
  ) => _preferences.setString(
    '${_key(owner, region)}.days',
    jsonEncode(
      days.map(
        (day, checked) => MapEntry(day, checked.toUtc().toIso8601String()),
      ),
    ),
  );

  Future<void> clear(String ownerUserId) async {
    for (final region in <String?>[null, 'china', 'global']) {
      await _preferences.remove(_key(ownerUserId, region));
      await _preferences.remove('${_key(ownerUserId, region)}.days');
    }
  }
}
