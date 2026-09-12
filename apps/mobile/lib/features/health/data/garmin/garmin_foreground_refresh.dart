import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/current_user.dart';
import '../../../../core/auth/domain_scope.dart';
import '../../../../core/auth/providers.dart' as auth;
import 'garmin_region_preference.dart';
import 'garmin_sync_controller.dart';

final garminForegroundAvailableProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS),
);

/// Mounted through the Health DomainPack. No OS task, background isolate,
/// notifications or permissions are involved in this foreground-only driver.
final garminForegroundRefreshProvider = Provider<GarminForegroundRefresh?>((
  ref,
) {
  if (!ref.watch(garminForegroundAvailableProvider)) return null;
  final enabled = ref.watch(
    auth.domainOptInsProvider.select(
      (value) => value.value?.contains(DomainScope.health) ?? false,
    ),
  );
  final owner = ref.watch(activeUserIdProvider);
  if (!enabled || owner == null) return null;
  ref.watch(garminRegionProvider);
  final controller = ref.read(garminSyncControllerProvider.notifier);
  final driver = GarminForegroundRefresh(
    refresh: () async {
      await controller.syncNow(automatic: true);
    },
    cancel: controller.cancelSync,
  );
  ref.onDispose(driver.stop);
  unawaited(
    Future<void>.microtask(() {
      if (ref.mounted) driver.start();
    }),
  );
  return driver;
});

/// The controller owns freshness and persisted retry policy. This timer merely
/// supplies opportunities while foregrounded, and never restarts a cancelled
/// import before its cooldown expires.
class GarminForegroundRefresh with WidgetsBindingObserver {
  GarminForegroundRefresh({required this.refresh, required this.cancel});
  final Future<void> Function() refresh;
  final Future<void> Function() cancel;
  bool _started = false;
  bool _stopped = false;
  bool _foreground = false;
  Timer? _timer;
  Future<void>? _inFlight;

  void start() {
    if (_started || _stopped) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) _resume();
  }

  void stop() {
    _stopped = true;
    _started = false;
    _foreground = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      final wasForeground = _foreground;
      _foreground = false;
      _timer?.cancel();
      _timer = null;
      if (wasForeground) unawaited(cancel().catchError((Object _) {}));
    }
    // Inactive can be a transient permission dialog; do not interrupt MFA.
  }

  void _resume() {
    if (!_started || _foreground) return;
    _foreground = true;
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(check()),
    );
    unawaited(check());
  }

  Future<void> check() {
    if (!_started || !_foreground) return Future<void>.value();
    return _inFlight ??= refresh()
        .catchError((Object _) {})
        .whenComplete(() => _inFlight = null);
  }
}
