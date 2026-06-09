/// Riverpod controller for Garmin Connect sync state.
///
/// Manages the full lifecycle: connect → auth → MFA → sync → disconnect.
/// Persists credentials via [GarminTokenStore] so sessions survive restarts.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/src/rust/api/health.dart' show GarminSyncProgress;

import '../providers.dart' show garminSnapshotWriterProvider;
import 'garmin_bridge.dart';
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
    if (_initialized) return;
    await _bridge.init(storedTokenJson: storedTokenJson, isCn: true);
    _initialized = true;
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
  Future<void> syncNow({
    Duration window = const Duration(days: 30),
  }) async {
    final now = DateTime.now().toUtc();
    state = GarminSyncing(startedAt: now);

    // Cancel any previous sync stream.
    await _syncSub?.cancel();

    try {
      await _ensureInit();
      final from = now.subtract(window);

      final completer = Completer<void>();
      _syncSub = _bridge.syncRangeWithProgress(from, now).listen(
        (progress) {
          state = GarminSyncing(
            startedAt: now,
            phase: progress.phase,
            currentDay: progress.current,
            totalDays: progress.total,
            metricsCount: progress.metricsCount,
            errors: progress.errors,
            // The "snapshot" event carries the HealthSnapshot JSON
            // in errors[0] — store it for persistence in onDone.
            snapshotJson: progress.phase == 'snapshot' && progress.errors.isNotEmpty
                ? progress.errors.first
                : (state is GarminSyncing
                    ? (state as GarminSyncing).snapshotJson
                    : null),
          );
        },
        onDone: () async {
          final s = state;
          if (s is GarminSyncing) {
            if (s.errors.isNotEmpty) {
              state = GarminError(s.errors.first);
            } else {
              // Persist the HealthSnapshot to Drift.
              await _persistSnapshot(s.snapshotJson);
              state = GarminConnected(
                lastSyncAt: now,
                totalMetrics: s.metricsCount,
              );
            }
          }
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e) {
          state = GarminError(e.toString());
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e) {
      state = GarminError(e.toString());
    }
  }

  /// Persist a HealthSnapshot JSON to the local Drift database.
  Future<void> _persistSnapshot(String? snapshotJson) async {
    if (snapshotJson == null || snapshotJson.isEmpty) return;
    try {
      final writer = await ref.read(garminSnapshotWriterProvider.future);
      await writer.writeSnapshotJson(snapshotJson);
    } catch (_) {
      // Non-fatal — sync data was fetched but not persisted.
      // The next sync will re-fetch via cursors.
    }
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
      await _tokenStore.clear();
      _initialized = false;
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
