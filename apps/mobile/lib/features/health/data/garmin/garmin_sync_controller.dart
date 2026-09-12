/// Owner-scoped Garmin sessions. All entry points share one import and all
/// native operations are serialized, including account/region transitions.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../health_refresh_coordinator.dart';
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

final garminBridgeProvider = Provider<GarminBridge>((ref) => GarminBridge());
final garminTokenStoreProvider = Provider<GarminTokenStore>(
  (ref) => GarminTokenStore(),
);
final garminClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final _garminQueueProvider = Provider<_GarminOperationQueue>(
  (ref) => _GarminOperationQueue(),
);

class GarminSyncController extends Notifier<GarminSyncState> {
  _GarminSession? _session;

  @override
  GarminSyncState build() {
    final owner = ref.watch(activeUserIdProvider);
    final region = ref.watch(garminRegionProvider);
    final enabled = ref.watch(
      auth.domainOptInsProvider.select(
        (value) => value.value?.contains(DomainScope.health) ?? false,
      ),
    );
    _session = null;
    if (owner == null || !enabled) return const GarminInitial();
    final session = _GarminSession(
      ref: ref,
      owner: owner,
      region: region,
      bridge: ref.watch(garminBridgeProvider),
      tokenStore: ref.watch(garminTokenStoreProvider),
      preferences: ref.watch(sharedPreferencesProvider),
      clock: ref.watch(garminClockProvider),
      queue: ref.watch(_garminQueueProvider),
      publish: (value) {
        if (ref.mounted) state = value;
      },
    );
    _session = session;
    ref.onDispose(session.dispose);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (session.active) unawaited(session.restore());
    });
    return const GarminInitial();
  }

  Future<void> restoreSession() async => _session?.restore();

  Future<HealthRefreshSourceResult> syncNow({
    Duration window = const Duration(days: 30),
    bool automatic = false,
  }) async =>
      await _session?.refresh(window: window, automatic: automatic) ??
      _garminSkipped;

  Future<void> connect(
    String email,
    String password, {
    required bool rememberPassword,
  }) async =>
      _session?.connect(email, password, rememberPassword: rememberPassword);

  Future<void> submitMfa(String code) async => _session?.submitMfa(code);
  Future<void> cancelSync() async => _session?.cancel();
  Future<void> disconnect() async => _session?.disconnect();
  Future<GarminSavedCredentials?> loadSavedCredentials() async =>
      _session?.tokenStore.loadCredentials(ownerUserId: _session!.owner);
}

final garminSyncControllerProvider =
    NotifierProvider<GarminSyncController, GarminSyncState>(
      GarminSyncController.new,
    );

const _garminSkipped = HealthRefreshSourceResult(
  source: HealthRefreshSource.garmin,
  outcome: HealthRefreshOutcome.skipped,
);

/// The Rust client is process-global. Keep auth, restore and imports serialized
/// even when Riverpod replaces an owner-scoped session.
class _GarminOperationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

class _GarminCancelled implements Exception {
  const _GarminCancelled();
}

class _GarminSession {
  _GarminSession({
    required this.ref,
    required this.owner,
    required this.region,
    required this.bridge,
    required this.tokenStore,
    required this.preferences,
    required this.clock,
    required this.queue,
    required this.publish,
  });

  final Ref ref;
  final String owner;
  final GarminRegion region;
  final GarminBridge bridge;
  final GarminTokenStore tokenStore;
  final SharedPreferences preferences;
  final DateTime Function() clock;
  final _GarminOperationQueue queue;
  final void Function(GarminSyncState) publish;
  bool active = true;
  bool initialized = false;
  bool cancelled = false;
  bool streaming = false;
  bool authenticating = false;
  GarminSyncState _state = const GarminInitial();
  GarminSyncState get state => _state;
  set state(GarminSyncState value) {
    if (!active) return;
    _state = value;
    publish(value);
  }

  Future<void>? restoreFuture;
  Future<void>? nativeCancellation;
  Future<HealthRefreshSourceResult>? refreshFuture;
  GarminSavedCredentials? pendingCredentials;
  bool rememberPassword = false;

  GarminSyncStatusStore get statusStore => GarminSyncStatusStore(preferences);
  GarminSyncStatus? get status => statusStore.read(owner, region: region.wire);

  void checkActive() {
    if (!active || !ref.mounted) throw const _GarminCancelled();
  }

  Future<T> guarded<T>(Future<T> work) async {
    final result = await work;
    checkActive();
    return result;
  }

  void dispose() {
    active = false;
    cancelled = true;
    if (streaming) unawaited(signalCancellation());
  }

  Future<void> signalCancellation({bool nativeStarted = false}) {
    // A cancel may reach Rust before the stream starts and resets its flag.
    // Re-send once after its start acknowledgement; drain both commands before
    // releasing the native queue so neither can cancel a replacement session.
    if (nativeStarted) {
      return nativeCancellation = (nativeCancellation ?? Future<void>.value())
          .then((_) => bridge.cancelSync())
          .catchError((Object _) {});
    }
    return nativeCancellation ??= bridge.cancelSync().catchError((Object _) {});
  }

  Future<void> cancel() async {
    cancelled = true;
    if (streaming) await signalCancellation();
    // Drain the native terminal event instead of cancelling the subscription.
    // This completes all waiters and serializes the next native operation.
    await refreshFuture;
  }
}
