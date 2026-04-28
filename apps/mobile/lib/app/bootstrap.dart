import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/format/formatters.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/crash_reporter.dart';
import '../core/logging/providers.dart';
import '../design_system/preferences/theme_preferences.dart';

/// Initializes the app shell: framework binding, URL strategy, and the global
/// error pipeline (Flutter framework errors, async zone errors, and the
/// platform dispatcher channel) all funnel through [AppLogger] → [CrashReporter].
///
/// Returns a [ProviderContainer] pre-seeded with the bootstrap logger and a
/// warm [SharedPreferences] handle so theme/market-color preferences resolve
/// synchronously on first build. The caller hosts it inside
/// `UncontrolledProviderScope`.
Future<ProviderContainer> bootstrap({AppConfig? config}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean URLs on web (e.g. /assets instead of /#/assets). No-op elsewhere.
  usePathUrlStrategy();
  await AppFormatters.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      if (config != null) appConfigProvider.overrideWithValue(config),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  // Force eager creation so AppLogger.instance is ready before any error
  // handler fires.
  final logger = container.read(loggerProvider);

  FlutterError.onError = (details) {
    logger.e(
      'Uncaught Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.e('Uncaught platform error', error: error, stackTrace: stack);
    return true;
  };

  if (kDebugMode) {
    logger.i('NaviWealth bootstrap complete (${logger.environment.name})');
  }
  return container;
}

/// Runs [body] inside a guarded zone so async errors bubble to [AppLogger].
/// Use this from `main()` to wrap `runApp(...)`.
Future<void> runGuarded(Future<void> Function() body) async {
  await runZonedGuarded(body, (error, stack) {
    AppLogger.instance.e(
      'Uncaught zone error',
      error: error,
      stackTrace: stack,
    );
  });
}
