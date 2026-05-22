import 'dart:async';

import 'package:flutter/widgets.dart';

import '../logging/app_logger.dart';
import 'sync_engine.dart';

/// Drives the SyncEngine on the cadences specified in
/// `docs/sync-v2.md` §7.4:
///   - App resumed → immediate sync
///   - Foreground → 30 s polling timer
///   - Manual "Sync now" → call [triggerNow]
class SyncScheduler with WidgetsBindingObserver {
  SyncScheduler({
    required SyncEngine engine,
    Duration interval = const Duration(seconds: 30),
    AppLogger? logger,
  }) : _engine = engine,
       _interval = interval,
       _logger = logger ?? AppLogger.instance;

  final SyncEngine _engine;
  final Duration _interval;
  final AppLogger _logger;
  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  bool _paused = false;

  /// Idempotent. Safe to call from `runApp` / `initState`.
  void start() {
    if (_started) return;
    _started = true;
    _logger.i('sync_scheduler: started (interval=${_interval.inSeconds}s)');
    WidgetsBinding.instance.addObserver(this);
    _restartTimer();
    // Kick a sync immediately so cold-start UI gets fresh data.
    unawaited(triggerNow());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _logger.i('sync_scheduler: stopped');
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
          _logger.d('sync_scheduler: app resumed');
          if (!_paused) unawaited(triggerNow());
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

  /// Pause sync. Used during backup restore to prevent concurrent mutations.
  void pause() {
    _paused = true;
    _logger.i('sync_scheduler: paused');
  }

  /// Resume sync and trigger an immediate cycle.
  void resume() {
    if (_paused) {
      _paused = false;
      _logger.i('sync_scheduler: resumed');
      unawaited(triggerNow());
    }
  }

  /// Run a sync cycle now. Concurrent calls share the same in-flight
  /// future thanks to [SyncEngine.run]'s mutex.
  Future<void> triggerNow() async {
    if (_paused) return;
    _logger.d('sync_scheduler: trigger');
    try {
      await _engine.run();
    } catch (e) {
      _logger.w('sync_scheduler: cycle error (non-fatal)', error: e);
    }
  }
}
