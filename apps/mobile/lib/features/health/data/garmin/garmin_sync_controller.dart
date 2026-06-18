/// Riverpod controller for Garmin Connect sync state.
///
/// Manages the full lifecycle: connect → auth → MFA → sync → disconnect.
/// Persists credentials via [GarminTokenStore] so sessions survive restarts.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/src/rust/api/health.dart' show GarminSyncProgress;

import '../../domain/health_metric.dart';
import '../../domain/health_metric_kind.dart';
import '../providers.dart'
    show garminSnapshotWriterProvider, healthMetricRepositoryProvider;
import 'garmin_bridge.dart';
import 'garmin_region_preference.dart';
import 'garmin_snapshot_writer.dart';
import 'garmin_sync_issue.dart';
import 'garmin_token_store.dart';

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

/// Garmin sync states (sealed, not freezed — avoids build_runner dep).
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

  /// HealthSnapshot JSON from Rust — set on the "snapshot" phase event.
  /// Null until the final snapshot arrives.
  final String? snapshotJson;
}

/// Error state.
class GarminError extends GarminSyncState {
  const GarminError(this.issue);
  final GarminSyncIssue issue;
}

/// Controller for Garmin sync operations.
class GarminSyncController extends Notifier<GarminSyncState> {
  @override
  GarminSyncState build() {
    // Kick off async restore after the route's first build burst. Restoring
    // may touch secure storage and the Rust bridge; doing it in a microtask
    // competes with the Health Today first frame during domain switches.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!ref.mounted) return;
      unawaited(_restoreSession());
    });
    return const GarminInitial();
  }

  final GarminBridge _bridge = GarminBridge();
  final GarminTokenStore _tokenStore = GarminTokenStore();
  bool _initialized = false;
  GarminRegion? _initializedRegion;
  StreamSubscription<GarminSyncProgress>? _syncSub;

  /// Try to restore a persisted Garmin session on startup.
  Future<void> _restoreSession() async {
    final stored = await _tokenStore.load();
    if (stored == null) return;

    state = const GarminRestoring();
    try {
      await _ensureInit(storedTokenJson: stored);
      final authState = await _bridge.authState();
      if (authState.canMakeRequests) {
        state = const GarminConnected();
      } else {
        // Token expired or invalid — clear stale persistence.
        await _tokenStore.clear();
        state = const GarminInitial();
      }
    } catch (_) {
      await _tokenStore.clear();
      state = const GarminInitial();
    }
  }

  /// Ensure the Rust-side Garmin client is initialized.
  /// Must be called before any other bridge method.
  Future<void> _ensureInit({String? storedTokenJson}) async {
    final region = ref.read(garminRegionProvider);
    if (_initialized && _initializedRegion == region) return;
    await _bridge.init(storedTokenJson: storedTokenJson, isCn: region.isCn);
    _initialized = true;
    _initializedRegion = region;
  }

  /// Connect with email/password.
  Future<void> connect(String email, String password) async {
    state = GarminSyncing(startedAt: DateTime.now().toUtc());
    try {
      await _ensureInit();
      final result = await _bridge.authenticate(email, password);
      switch (result.type) {
        case GarminAuthResultType.authenticated:
          await _persistSession();
          state = const GarminConnected();
        case GarminAuthResultType.mfaRequired:
          state = const GarminPendingMfa();
        case GarminAuthResultType.failed:
          state = GarminError(
            GarminSyncIssue.fromLegacyMessage(
              result.errorMessage ?? 'auth failed',
            ),
          );
      }
    } catch (e) {
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
  }

  /// Submit MFA code.
  Future<void> submitMfa(String code) async {
    try {
      await _ensureInit();
      final result = await _bridge.submitMfa(code);
      switch (result.type) {
        case GarminAuthResultType.authenticated:
          await _persistSession();
          state = const GarminConnected();
        case GarminAuthResultType.mfaRequired:
          state = const GarminPendingMfa();
        case GarminAuthResultType.failed:
          state = GarminError(
            GarminSyncIssue.fromLegacyMessage(
              result.errorMessage ?? 'MFA failed',
            ),
          );
      }
    } catch (e) {
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
  }

  /// Sync recent data with streaming progress updates.
  Future<void> syncNow({Duration window = const Duration(days: 30)}) async {
    final now = DateTime.now().toUtc();
    state = GarminSyncing(startedAt: now);
    final logger = AppLogger.instance;
    final region = ref.read(garminRegionProvider);

    // Cancel any previous sync stream.
    await _syncSub?.cancel();

    try {
      await _ensureInit();
      final ranges = await _missingGarminRanges(now: now, window: window);
      logger.i(
        'HealthOS Garmin sync start: region=${region.label} '
        'windowDays=${window.inDays} missingRanges=${ranges.length} '
        'missingDays=${ranges.fold<int>(0, (sum, range) => sum + range.days)} '
        'ranges=${ranges.map((r) => r.label).toList()}',
      );

      if (ranges.isEmpty) {
        logger.i('HealthOS Garmin sync skipped: no missing days');
        state = GarminConnected(lastSyncAt: now);
        return;
      }

      var totalPersisted = 0;
      final allIssues = <GarminSyncIssue>[];
      for (var index = 0; index < ranges.length; index += 1) {
        final result = await _syncRange(
          range: ranges[index],
          startedAt: now,
          rangeIndex: index,
          rangeCount: ranges.length,
          logger: logger,
        );
        totalPersisted += result.persistedMetrics;
        allIssues.addAll(result.issues);
        final fatalIssues = allIssues.fatal;
        if (fatalIssues.isNotEmpty) {
          if (fatalIssues.requiresReconnect) {
            await _clearStaleSession();
            logger.w('HealthOS Garmin stale session cleared after auth error');
          }
          logger.w(
            'HealthOS Garmin sync failed: ${fatalIssues.first.logLabel}',
          );
          state = GarminError(fatalIssues.first);
          return;
        }
      }

      logger.i('HealthOS Garmin sync success: totalMetrics=$totalPersisted');
      state = GarminConnected(lastSyncAt: now, totalMetrics: totalPersisted);
    } catch (e) {
      logger.e('HealthOS Garmin sync exception', error: e);
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
  }

  Future<_GarminRangeSyncResult> _syncRange({
    required _GarminDateRange range,
    required DateTime startedAt,
    required int rangeIndex,
    required int rangeCount,
    required AppLogger logger,
  }) async {
    final completer = Completer<_GarminRangeSyncResult>();
    GarminSyncing? latest;
    _syncSub = _bridge
        .syncRangeWithProgress(range.from, range.to)
        .listen(
          (progress) {
            final issues = parseGarminSyncIssues(progress.errors);
            logger.i(
              'HealthOS Garmin progress: range=${rangeIndex + 1}/$rangeCount '
              '${range.label} phase=${progress.phase} '
              'current=${progress.current}/${progress.total} '
              'metrics=${progress.metricsCount} '
              'issues=${issues.length} '
              'snapshotBytes=${progress.snapshotJson?.length ?? 0}',
            );
            if (issues.isNotEmpty) {
              logger.w(
                'HealthOS Garmin progress issues: '
                '${issues.map((issue) => issue.logLabel).toList()}',
              );
            }
            latest = GarminSyncing(
              startedAt: startedAt,
              phase: progress.phase,
              currentDay: progress.current,
              totalDays: progress.total,
              metricsCount: progress.metricsCount,
              issues: issues,
              snapshotJson: progress.snapshotJson ?? latest?.snapshotJson,
            );
            state = latest!;
          },
          onDone: () async {
            final s = latest;
            if (s == null) {
              completer.complete(
                const _GarminRangeSyncResult(
                  persistedMetrics: 0,
                  issues: <GarminSyncIssue>[],
                ),
              );
              return;
            }
            logger.i(
              'HealthOS Garmin stream done: range=${range.label} '
              'phase=${s.phase} metrics=${s.metricsCount} '
              'issues=${s.issues.length} '
              'snapshotBytes=${s.snapshotJson?.length ?? 0}',
            );
            final writeResult = await _persistSnapshot(s.snapshotJson);
            logger.i(
              'HealthOS Garmin persist result: range=${range.label} '
              'total=${writeResult?.total ?? 0} '
              'upserted=${writeResult?.upserted ?? 0} '
              'unchanged=${writeResult?.unchanged ?? 0} '
              'errors=${writeResult?.errors ?? const <String>[]}',
            );
            ref.invalidate(healthMetricRepositoryProvider);
            final issues = <GarminSyncIssue>[
              ...s.issues,
              ..._snapshotPersistIssues(
                metricsCount: s.metricsCount,
                hasSnapshotJson:
                    s.snapshotJson != null && s.snapshotJson!.isNotEmpty,
                writeResult: writeResult,
              ),
              if (writeResult != null)
                ...writeResult.errors.map(GarminSyncIssue.fromLegacyMessage),
            ];
            completer.complete(
              _GarminRangeSyncResult(
                persistedMetrics: writeResult?.total ?? s.metricsCount,
                issues: issues,
              ),
            );
          },
          onError: (Object e) {
            logger.e('HealthOS Garmin stream error', error: e);
            completer.complete(
              _GarminRangeSyncResult(
                persistedMetrics: 0,
                issues: [GarminSyncIssue.fromLegacyMessage(e.toString())],
              ),
            );
          },
          cancelOnError: true,
        );

    return completer.future;
  }

  Future<List<_GarminDateRange>> _missingGarminRanges({
    required DateTime now,
    required Duration window,
  }) async {
    final to = _dayStartUtc(now);
    final from = to.subtract(Duration(days: window.inDays));
    final expected = <DateTime>[
      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) d,
    ];
    final covered = await _garminCoveredDays(limit: expected.length + 10);
    final missing = expected
        .where((day) => !covered.contains(day))
        .toList(growable: false);
    return _compressDays(missing);
  }

  Future<Set<DateTime>> _garminCoveredDays({required int limit}) async {
    final repo = await ref.read(healthMetricRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final rows = await repo.listByKinds(
      ownerUserId: userId,
      kinds: _kGarminCoverageKinds,
      limit: limit,
    );
    final covered = <DateTime>{};
    for (final metrics in rows.values) {
      for (final metric in metrics) {
        if (!_isGarminMetric(metric)) continue;
        covered.add(_dayStartUtc(metric.capturedAt));
      }
    }
    return covered;
  }

  List<_GarminDateRange> _compressDays(List<DateTime> days) {
    if (days.isEmpty) return const <_GarminDateRange>[];
    final sorted = List<DateTime>.of(days)..sort();
    final ranges = <_GarminDateRange>[];
    var start = sorted.first;
    var end = sorted.first;
    for (final day in sorted.skip(1)) {
      if (day.difference(end).inDays == 1) {
        end = day;
        continue;
      }
      ranges.add(_GarminDateRange(start, end));
      start = day;
      end = day;
    }
    ranges.add(_GarminDateRange(start, end));
    return ranges;
  }

  bool _isGarminMetric(HealthMetric metric) {
    return metric.id.startsWith('garmin:') ||
        (metric.sourceDevice?.toLowerCase() == 'garmin');
  }

  DateTime _dayStartUtc(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  /// Persist a HealthSnapshot JSON to the local Drift database.
  Future<GarminWriteResult?> _persistSnapshot(String? snapshotJson) async {
    final logger = AppLogger.instance;
    if (snapshotJson == null || snapshotJson.isEmpty) {
      logger.w('HealthOS Garmin persist skipped: empty snapshotJson');
      return null;
    }
    try {
      logger.i('HealthOS Garmin persist start: bytes=${snapshotJson.length}');
      final writer = await ref.read(garminSnapshotWriterProvider.future);
      return writer.writeSnapshotJson(snapshotJson);
    } catch (e) {
      logger.e('HealthOS Garmin persist exception', error: e);
      return GarminWriteResult(
        upserted: 0,
        unchanged: 0,
        errors: [GarminSyncIssue.persistFailed(e).message],
      );
    }
  }

  List<GarminSyncIssue> _snapshotPersistIssues({
    required int metricsCount,
    required bool hasSnapshotJson,
    required GarminWriteResult? writeResult,
  }) {
    if (metricsCount <= 0) return const <GarminSyncIssue>[];
    if (!hasSnapshotJson) {
      return [GarminSyncIssue.noSnapshot()];
    }
    if (writeResult == null) {
      return [GarminSyncIssue.notPersisted()];
    }
    if (writeResult.total == 0) {
      return [GarminSyncIssue.unsupportedSnapshot()];
    }
    return const <GarminSyncIssue>[];
  }

  Future<void> _clearStaleSession() async {
    await _tokenStore.clear();
    _initialized = false;
    _initializedRegion = null;
  }

  /// Cancel an in-progress sync.
  Future<void> cancelSync() async {
    await _bridge.cancelSync();
    await _syncSub?.cancel();
    _syncSub = null;
    state = const GarminConnected();
  }

  /// Disconnect and clear credentials.
  Future<void> disconnect() async {
    try {
      await _ensureInit();
      await _bridge.logout();
      await _clearStaleSession();
      state = const GarminInitial();
    } catch (e) {
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
  }

  /// Export session from Rust and persist to secure storage.
  Future<void> _persistSession() async {
    try {
      final json = await _bridge.exportSession();
      if (json != null) await _tokenStore.save(json);
    } catch (_) {
      // Non-fatal — user can still use the session this launch.
    }
  }
}

/// Provider for the Garmin sync controller.
final garminSyncControllerProvider =
    NotifierProvider<GarminSyncController, GarminSyncState>(
      GarminSyncController.new,
    );

class _GarminDateRange {
  const _GarminDateRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  int get days => to.difference(from).inDays + 1;

  String get label =>
      days == 1 ? _formatDay(from) : '${_formatDay(from)}..${_formatDay(to)}';

  static String _formatDay(DateTime value) {
    final utc = value.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }
}

class _GarminRangeSyncResult {
  const _GarminRangeSyncResult({
    required this.persistedMetrics,
    required this.issues,
  });

  final int persistedMetrics;
  final List<GarminSyncIssue> issues;
}
