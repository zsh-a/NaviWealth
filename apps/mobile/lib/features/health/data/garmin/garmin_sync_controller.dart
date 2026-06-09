/// Riverpod controller for Garmin Connect sync state.
///
/// Manages the full lifecycle: connect → auth → MFA → sync → disconnect.
/// Persists credentials via [GarminTokenStore] so sessions survive restarts.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const GarminSyncing({required this.startedAt});
  final DateTime startedAt;
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

  /// Sync recent data.
  Future<void> syncNow({
    Duration window = const Duration(days: 30),
  }) async {
    final now = DateTime.now().toUtc();
    state = GarminSyncing(startedAt: now);
    try {
      await _ensureInit();
      final from = now.subtract(window);
      final outcomes = await _bridge.syncRange(from, now);

      final totalMetrics =
          outcomes.fold<int>(0, (sum, o) => sum + o.metricsCount);
      final errors = outcomes.expand((o) => o.errors).toList();

      if (errors.isNotEmpty) {
        state = GarminError(errors.first);
      } else {
        state = GarminConnected(
          lastSyncAt: now,
          totalMetrics: totalMetrics,
        );
      }
    } catch (e) {
      state = GarminError(e.toString());
    }
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
