part of 'garmin_sync_controller.dart';

const Set<HealthMetricKind> _kGarminCoverageKinds = <HealthMetricKind>{
  HealthMetricKind.stepsDaily,
  HealthMetricKind.hrvDaily,
  HealthMetricKind.rhrDaily,
  HealthMetricKind.stressDaily,
  HealthMetricKind.bodyBatteryDaily,
  HealthMetricKind.spo2Daily,
  HealthMetricKind.respiratoryRateDaily,
  HealthMetricKind.distanceWalkingRunningDaily,
};

/// Garmin sync states (sealed, not freezed - avoids build_runner dep).
sealed class GarminSyncState {
  const GarminSyncState();
}

/// Not connected.
class GarminInitial extends GarminSyncState {
  const GarminInitial();
}

/// Restoring a persisted session.
class GarminRestoring extends GarminSyncState {
  const GarminRestoring();
}

/// MFA code required.
class GarminPendingMfa extends GarminSyncState {
  const GarminPendingMfa();
}

/// Connected and idle.
class GarminConnected extends GarminSyncState {
  const GarminConnected({this.lastSyncAt, this.totalMetrics = 0});
  final DateTime? lastSyncAt;
  final int totalMetrics;
}

/// Sync in progress.
class GarminSyncing extends GarminSyncState {
  const GarminSyncing({
    required this.startedAt,
    this.currentDay = 0,
    this.totalDays = 0,
    this.metricsCount = 0,
    this.phase = '',
    this.issues = const [],
    this.snapshotJson,
  });
  final DateTime startedAt;
  final int currentDay;
  final int totalDays;
  final int metricsCount;
  final String phase;
  final List<GarminSyncIssue> issues;

  /// HealthSnapshot JSON from Rust; set on the "snapshot" phase event.
  /// Null until the final snapshot arrives.
  final String? snapshotJson;
}

/// Error state.
class GarminError extends GarminSyncState {
  const GarminError(this.issue);
  final GarminSyncIssue issue;
}

GarminSyncIssue garminRestoreAuthIssue(GarminAuthState authState) {
  final detail = switch (authState.type) {
    GarminAuthStateType.error => authState.errorMessage ?? 'Garmin auth failed',
    GarminAuthStateType.unauthenticated => 'Garmin token expired',
    GarminAuthStateType.refreshing => 'Garmin token expired',
    GarminAuthStateType.pendingMfa => 'Garmin auth failed: pending MFA',
    GarminAuthStateType.authenticated => 'Garmin auth failed',
  };
  return GarminSyncIssue.fromLegacyMessage(detail);
}
