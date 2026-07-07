/// Foreground catch-up scheduler for registered agents.
///
/// Domain-specific native background hooks only cover a few notification-style
/// agents. This scheduler drives the full active [AgentRunController.tick]
/// inventory when the app starts or returns to the foreground, while leaving
/// due/not-due policy inside each [AgentSchedule].
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../logging/app_logger.dart';

typedef AgentForegroundTick = Future<int> Function(DateTime now);

class AgentForegroundScheduler with WidgetsBindingObserver {
  AgentForegroundScheduler({
    required AgentForegroundTick tick,
    DateTime Function()? clock,
    AppLogger? logger,
  }) : _tick = tick,
       _clock = clock ?? DateTime.now,
       _logger = logger;

  final AgentForegroundTick _tick;
  final DateTime Function() _clock;
  final AppLogger? _logger;

  bool _started = false;
  bool _foreground = true;
  Future<void>? _inFlight;

  /// Idempotent. Safe to call from app bootstrap.
  void start() {
    if (_started) return;
    _started = true;
    _logger?.i('agent_foreground_scheduler: started');
    WidgetsBinding.instance.addObserver(this);
    unawaited(triggerNow());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _logger?.i('agent_foreground_scheduler: stopped');
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final wasBackgrounded = !_foreground;
        _foreground = true;
        if (wasBackgrounded) {
          _logger?.d('agent_foreground_scheduler: app resumed');
          unawaited(triggerNow());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foreground = false;
    }
  }

  /// Run one catch-up tick now. Concurrent triggers share the same in-flight
  /// work so a resume event cannot stack duplicate agent sweeps.
  Future<void> triggerNow() {
    final current = _inFlight;
    if (current != null) return current;
    final future = _runTick();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _runTick() async {
    try {
      final ranCount = await _tick(_clock().toUtc());
      if (ranCount > 0) {
        _logger?.i(
          'agent_foreground_scheduler: catch-up ran $ranCount agent(s)',
        );
      } else {
        _logger?.d('agent_foreground_scheduler: no due agents');
      }
    } on Object catch (error, stackTrace) {
      _logger?.w(
        'agent_foreground_scheduler: catch-up failed (non-fatal)',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
