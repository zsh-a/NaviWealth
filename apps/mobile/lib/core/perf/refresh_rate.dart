import 'package:flutter/widgets.dart';

/// Returns the device's primary view refresh rate, defaulting to 60 Hz when
/// no view is mounted yet.
///
/// Safe to call after `WidgetsFlutterBinding.ensureInitialized()`.
double primaryRefreshRate() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return 60.0;
  return views.first.display.refreshRate;
}

/// The target FPS used to size the GlassPerformanceMonitor budget and the
/// GlassAdaptiveScope `targetFrameMs`. ProMotion / 120 Hz panels stay at
/// 120; everything else falls back to 60 to avoid permanent
/// "over-budget" misclassification.
int targetFps() => primaryRefreshRate() >= 90 ? 120 : 60;

/// Frame budget in microseconds matching [targetFps].
int targetFrameBudgetUs() => (1000000 / targetFps()).round();

/// Frame budget in milliseconds (rounded), suitable for
/// `GlassAdaptiveScopeConfig.targetFrameMs`.
int targetFrameBudgetMs() => (1000 / targetFps()).round();
