/// Riverpod controller for Garmin Connect sync state.
///
/// Manages the full lifecycle: connect → auth → MFA → sync → disconnect.
/// UI binds to [GarminSyncState] for reactive updates.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'garmin_bridge.dart';

/// Garmin sync states (sealed, not freezed — avoids build_runner dep).
sealed class GarminSyncState {
  const GarminSyncState();
}

/// Not connected.
class GarminInitial extends GarminSyncState {
  const GarminInitial();
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
  GarminSyncState build() => const GarminInitial();

  final GarminBridge _bridge = GarminBridge();
  bool _initialized = false;

  /// Ensure the Rust-side Garmin client is initialized.
  /// Must be called before any other bridge method.
  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _bridge.init(isCn: true);
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
      _initialized = false;
      state = const GarminInitial();
    } catch (e) {
      state = GarminError(e.toString());
    }
  }
}

/// Provider for the Garmin sync controller.
final garminSyncControllerProvider =
    NotifierProvider<GarminSyncController, GarminSyncState>(
  GarminSyncController.new,
);
