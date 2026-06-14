/// Riverpod controller for Garmin Connect sync state.
///
/// Manages the full lifecycle: connect → auth → MFA → sync → disconnect.
/// Persists credentials via [GarminTokenStore] so sessions survive restarts.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/src/rust/api/health.dart' show GarminSyncProgress;

import '../providers.dart'
    show garminSnapshotWriterProvider, healthMetricRepositoryProvider;
import 'garmin_bridge.dart';
import 'garmin_region_preference.dart';
import 'garmin_snapshot_writer.dart';
import 'garmin_sync_issue.dart';
import 'garmin_token_store.dart';

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
    // Kick off async restore; state transitions happen via _restoreSession.
    Future.microtask(_restoreSession);
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
      final from = now.subtract(window);
      logger.i(
        'HealthOS Garmin sync start: region=${region.label} '
        'from=${from.toIso8601String()} to=${now.toIso8601String()} '
        'windowDays=${window.inDays}',
      );

      final completer = Completer<void>();
      _syncSub = _bridge
          .syncRangeWithProgress(from, now)
          .listen(
            (progress) {
              final issues = parseGarminSyncIssues(progress.errors);
              logger.i(
                'HealthOS Garmin progress: phase=${progress.phase} '
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
              state = GarminSyncing(
                startedAt: now,
                phase: progress.phase,
                currentDay: progress.current,
                totalDays: progress.total,
                metricsCount: progress.metricsCount,
                issues: issues,
                // The "snapshot" event carries the HealthSnapshot JSON
                // in the dedicated snapshotJson field.
                snapshotJson:
                    progress.snapshotJson ??
                    (state is GarminSyncing
                        ? (state as GarminSyncing).snapshotJson
                        : null),
              );
            },
            onDone: () async {
              final s = state;
              if (s is GarminSyncing) {
                logger.i(
                  'HealthOS Garmin stream done: phase=${s.phase} '
                  'metrics=${s.metricsCount} issues=${s.issues.length} '
                  'snapshotBytes=${s.snapshotJson?.length ?? 0}',
                );
                // Persist whatever snapshot Rust produced before surfacing
                // partial endpoint errors. A failed optional endpoint should not
                // discard successfully fetched sleep/HR/steps/workouts.
                final writeResult = await _persistSnapshot(s.snapshotJson);
                logger.i(
                  'HealthOS Garmin persist result: '
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
                    ...writeResult.errors.map(
                      GarminSyncIssue.fromLegacyMessage,
                    ),
                ];
                final fatalIssues = issues.fatal;
                if (fatalIssues.isNotEmpty) {
                  if (fatalIssues.requiresReconnect) {
                    await _clearStaleSession();
                    logger.w(
                      'HealthOS Garmin stale session cleared after auth error',
                    );
                  }
                  logger.w(
                    'HealthOS Garmin sync failed: '
                    '${fatalIssues.first.logLabel}',
                  );
                  state = GarminError(fatalIssues.first);
                } else {
                  logger.i(
                    'HealthOS Garmin sync success: '
                    'totalMetrics=${writeResult?.total ?? s.metricsCount}',
                  );
                  state = GarminConnected(
                    lastSyncAt: now,
                    totalMetrics: writeResult?.total ?? s.metricsCount,
                  );
                }
              }
              if (!completer.isCompleted) completer.complete();
            },
            onError: (Object e) {
              logger.e('HealthOS Garmin stream error', error: e);
              state = GarminError(
                GarminSyncIssue.fromLegacyMessage(e.toString()),
              );
              if (!completer.isCompleted) completer.complete();
            },
            cancelOnError: true,
          );

      await completer.future;
    } catch (e) {
      logger.e('HealthOS Garmin sync exception', error: e);
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
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
