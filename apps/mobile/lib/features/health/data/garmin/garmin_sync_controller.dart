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
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/src/rust/api/health.dart' show GarminSyncProgress;

import '../../domain/health_metric.dart';
import '../../domain/health_metric_kind.dart';
import '../providers.dart'
    show garminSnapshotWriterProvider, healthMetricRepositoryProvider;
import 'garmin_bridge.dart';
import 'garmin_region_preference.dart';
import 'garmin_snapshot_writer.dart';
import 'garmin_sync_issue.dart';
import 'garmin_sync_status_store.dart';
import 'garmin_token_store.dart';

part 'garmin_sync_controller_persistence.dart';
part 'garmin_sync_controller_ranges.dart';
part 'garmin_sync_controller_session.dart';
part 'garmin_sync_controller_state.dart';
part 'garmin_sync_controller_sync.dart';

/// Controller for Garmin sync operations.
class GarminSyncController extends Notifier<GarminSyncState>
    with
        GarminSyncControllerRangeMixin,
        GarminSyncControllerPersistenceMixin,
        GarminSyncControllerSessionMixin,
        GarminSyncControllerSyncMixin {
  @override
  GarminSyncState build() {
    final ownerUserId = ref.watch(activeUserIdProvider);
    _initialized = false;
    _initializedRegion = null;
    _pendingCredentials = null;
    _pendingRememberPassword = false;
    // Kick off async restore after the route's first build burst. Restoring
    // may touch secure storage and the Rust bridge; doing it in a microtask
    // competes with the Health Today first frame during domain switches.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!ref.mounted || ownerUserId == null) return;
      unawaited(_restoreSession());
    });
    return const GarminInitial();
  }

  @override
  final GarminBridge _bridge = GarminBridge();
  @override
  final GarminTokenStore _tokenStore = GarminTokenStore();
  @override
  bool _initialized = false;
  @override
  GarminRegion? _initializedRegion;
  @override
  StreamSubscription<GarminSyncProgress>? _syncSub;
  @override
  GarminSavedCredentials? _pendingCredentials;
  @override
  bool _pendingRememberPassword = false;
}

/// Provider for the Garmin sync controller.
final garminSyncControllerProvider =
    NotifierProvider<GarminSyncController, GarminSyncState>(
      GarminSyncController.new,
    );
