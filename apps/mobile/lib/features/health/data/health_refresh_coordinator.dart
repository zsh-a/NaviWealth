import 'dart:async';

import 'health_sync_service.dart';

enum HealthRefreshSource { platform, garmin }

enum HealthRefreshOutcome { synced, skipped, failed }

class HealthRefreshSourceResult {
  const HealthRefreshSourceResult({
    required this.source,
    required this.outcome,
    this.imported = 0,
    this.unchanged = 0,
    this.errorCode,
  });

  final HealthRefreshSource source;
  final HealthRefreshOutcome outcome;
  final int imported;
  final int unchanged;
  final String? errorCode;

  bool get failed => outcome == HealthRefreshOutcome.failed;
  bool get synced => outcome == HealthRefreshOutcome.synced;
}

class HealthRefreshResult {
  const HealthRefreshResult({
    required this.startedAt,
    required this.completedAt,
    required this.sources,
  });

  final DateTime startedAt;
  final DateTime completedAt;
  final List<HealthRefreshSourceResult> sources;

  int get syncedCount => sources.where((source) => source.synced).length;
  int get failedCount => sources.where((source) => source.failed).length;
  bool get hasFailures => failedCount > 0;
}

typedef GarminRefresh = Future<HealthRefreshSourceResult> Function();

/// Coordinates the user-facing "refresh" action across every connected
/// HealthOS source. A single in-flight future is shared by pull-to-refresh,
/// Today source cards, and Settings so duplicate imports cannot race.
class HealthRefreshCoordinator {
  HealthRefreshCoordinator({
    required HealthSyncService platform,
    required GarminRefresh refreshGarmin,
    DateTime Function()? clock,
  }) : _platform = platform,
       _refreshGarmin = refreshGarmin,
       _clock = clock ?? _defaultClock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  final HealthSyncService _platform;
  final GarminRefresh _refreshGarmin;
  final DateTime Function() _clock;
  Future<HealthRefreshResult>? _activeRefresh;

  Future<HealthRefreshResult> refreshConnectedSources() {
    return _activeRefresh ??= _refreshConnectedSources().whenComplete(
      () => _activeRefresh = null,
    );
  }

  Future<HealthRefreshSourceResult> connectAndSyncPlatform() async {
    try {
      if (!await _platform.isAvailable()) {
        return const HealthRefreshSourceResult(
          source: HealthRefreshSource.platform,
          outcome: HealthRefreshOutcome.skipped,
          errorCode: 'health-platform-unavailable',
        );
      }
      if (!await _platform.hasPermissions() &&
          !await _platform.requestPermissions()) {
        final skipped = HealthSyncResult.skipped(
          startedAt: _clock(),
          errorMessage: 'health-platform-permission-denied',
        );
        await _platform.recordResult(skipped);
        return const HealthRefreshSourceResult(
          source: HealthRefreshSource.platform,
          outcome: HealthRefreshOutcome.failed,
          errorCode: 'health-platform-permission-denied',
        );
      }
      return await _syncPlatform();
    } on Object {
      return const HealthRefreshSourceResult(
        source: HealthRefreshSource.platform,
        outcome: HealthRefreshOutcome.failed,
        errorCode: 'health-platform-refresh-failed',
      );
    }
  }

  Future<HealthRefreshResult> _refreshConnectedSources() async {
    final startedAt = _clock();
    final sources = <HealthRefreshSourceResult>[];

    try {
      if (await _platform.isAvailable() && await _platform.hasPermissions()) {
        sources.add(await _syncPlatform());
      } else {
        sources.add(
          const HealthRefreshSourceResult(
            source: HealthRefreshSource.platform,
            outcome: HealthRefreshOutcome.skipped,
          ),
        );
      }
    } on Object {
      sources.add(
        const HealthRefreshSourceResult(
          source: HealthRefreshSource.platform,
          outcome: HealthRefreshOutcome.failed,
          errorCode: 'health-platform-refresh-failed',
        ),
      );
    }

    try {
      sources.add(await _refreshGarmin());
    } on Object {
      sources.add(
        const HealthRefreshSourceResult(
          source: HealthRefreshSource.garmin,
          outcome: HealthRefreshOutcome.failed,
          errorCode: 'garmin-refresh-failed',
        ),
      );
    }
    return HealthRefreshResult(
      startedAt: startedAt,
      completedAt: _clock(),
      sources: List<HealthRefreshSourceResult>.unmodifiable(sources),
    );
  }

  Future<HealthRefreshSourceResult> _syncPlatform() async {
    final result = await _platform.syncRange();
    return HealthRefreshSourceResult(
      source: HealthRefreshSource.platform,
      outcome: result.ok
          ? HealthRefreshOutcome.synced
          : HealthRefreshOutcome.failed,
      imported: result.upserted,
      unchanged: result.unchanged,
      errorCode: result.errorMessage,
    );
  }
}
