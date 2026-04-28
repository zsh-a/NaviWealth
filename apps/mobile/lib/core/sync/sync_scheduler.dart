import 'dart:async';

import 'package:flutter/widgets.dart';

import 'sync_engine.dart';

/// Drives the SyncEngine on the cadences specified in
/// `docs/sync-protocol.md` §7.3:
///   - App resumed → immediate sync
///   - Foreground → 30 s polling timer
///   - Manual "Sync now" → call [triggerNow]
///
/// Mobile background ticks (BackgroundTasks / WorkManager) and Web
/// `Periodic Background Sync` are wired by the platform shell — this
/// scheduler only owns the foreground story so the same code path is
/// exercised on every platform's main thread.
class SyncScheduler with WidgetsBindingObserver {
  SyncScheduler({
    required SyncEngine engine,
    Duration interval = const Duration(seconds: 30),
  }) : _engine = engine,
       _interval = interval;

  final SyncEngine _engine;
  final Duration _interval;
  Timer? _timer;
  bool _started = false;
  bool _foreground = true;

  /// Idempotent. Safe to call from `runApp` / `initState`.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _restartTimer();
    // Kick a sync immediately so cold-start UI gets fresh data.
    unawaited(triggerNow());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_foreground) {
          _foreground = true;
          unawaited(triggerNow());
        }
        _restartTimer();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foreground = false;
        _timer?.cancel();
        _timer = null;
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(triggerNow()));
  }

  /// Run a sync cycle now. Concurrent calls share the same in-flight
  /// future thanks to [SyncEngine.run]'s mutex.
  Future<void> triggerNow() async {
    try {
      await _engine.run();
    } catch (_) {
      // Engine internalises errors into its status bus; we swallow here
      // so timer ticks don't propagate exceptions out of unawaited futures.
    }
  }
}
