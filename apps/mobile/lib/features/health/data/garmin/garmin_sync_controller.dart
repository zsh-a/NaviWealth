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
    this.errors = const [],
    this.snapshotJson,
  });
  final DateTime startedAt;
  final int currentDay;
  final int totalDays;
  final int metricsCount;
  final String phase;
  final List<String> errors;

  /// HealthSnapshot JSON from Rust — set on the "snapshot" phase event.
  /// Null until the final snapshot arrives.
  final String? snapshotJson;
}

/// Error state.
class GarminError extends GarminSyncState {
  const GarminError(this.message);
  final String message;
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
          state = GarminError(result.errorMessage ?? 'auth failed');
      }
    } catch (e) {
      state = GarminError(e.toString());
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
          state = GarminError(result.errorMessage ?? 'MFA failed');
      }
    } catch (e) {
      state = GarminError(e.toString());
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
              logger.i(
                'HealthOS Garmin progress: phase=${progress.phase} '
                'current=${progress.current}/${progress.total} '
                'metrics=${progress.metricsCount} '
                'errors=${progress.errors.length} '
                'snapshotBytes=${progress.snapshotJson?.length ?? 0}',
              );
              if (progress.errors.isNotEmpty) {
                logger.w('HealthOS Garmin progress errors: ${progress.errors}');
              }
              state = GarminSyncing(
                startedAt: now,
                phase: progress.phase,
                currentDay: progress.current,
                totalDays: progress.total,
                metricsCount: progress.metricsCount,
                errors: progress.errors,
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
                  'metrics=${s.metricsCount} errors=${s.errors.length} '
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
                final errors = _fatalSyncErrors(<String>[
                  ...s.errors,
                  ..._snapshotPersistErrors(
                    metricsCount: s.metricsCount,
                    hasSnapshotJson:
                        s.snapshotJson != null && s.snapshotJson!.isNotEmpty,
                    writeResult: writeResult,
                  ),
                  if (writeResult != null) ...writeResult.errors,
                ]);
                if (errors.isNotEmpty) {
                  if (_hasGarminAuthExpiredError(errors)) {
                    await _clearStaleSession();
                    logger.w(
                      'HealthOS Garmin stale session cleared after auth error',
                    );
                  }
                  logger.w('HealthOS Garmin sync failed: ${errors.first}');
                  state = GarminError(errors.first);
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
              state = GarminError(e.toString());
              if (!completer.isCompleted) completer.complete();
            },
            cancelOnError: true,
          );

      await completer.future;
    } catch (e) {
      logger.e('HealthOS Garmin sync exception', error: e);
      state = GarminError(e.toString());
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
        errors: ['persist snapshot failed: $e'],
      );
    }
  }

  List<String> _snapshotPersistErrors({
    required int metricsCount,
    required bool hasSnapshotJson,
    required GarminWriteResult? writeResult,
  }) {
    if (metricsCount <= 0) return const <String>[];
    if (!hasSnapshotJson) {
      return const <String>['Garmin sync produced metrics but no snapshot'];
    }
    if (writeResult == null) {
      return const <String>['Garmin snapshot was not persisted'];
    }
    if (writeResult.total == 0) {
      return const <String>[
        'Garmin snapshot did not contain supported HealthSnapshot rows',
      ];
    }
    return const <String>[];
  }

  List<String> _fatalSyncErrors(List<String> errors) {
    return errors
        .where((e) => !_isOptionalGarminEndpointError(e))
        .toList(growable: false);
  }

  bool _isOptionalGarminEndpointError(String error) {
    final lower = error.toLowerCase();
    return lower.startsWith('activities fetch failed:') &&
        (lower.contains('404 not found') ||
            lower.contains('garmin api error: 404'));
  }

  bool _hasGarminAuthExpiredError(List<String> errors) {
    return errors.any((error) {
      final lower = error.toLowerCase();
      return lower.contains('di token refresh failed') ||
          lower.contains('401 unauthorized') ||
          lower.contains('token expired') ||
          lower.contains('token may be expired') ||
          lower.contains('garmin auth failed');
    });
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
      state = GarminError(e.toString());
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
