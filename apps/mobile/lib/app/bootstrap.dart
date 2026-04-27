import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import '../core/logging/app_logger.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean URLs on web (e.g. /assets instead of /#/assets). No-op elsewhere.
  usePathUrlStrategy();
  FlutterError.onError = (details) {
    AppLogger.instance.e(
      'Uncaught Flutter error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  if (kDebugMode) {
    AppLogger.instance.i('NaviWealth bootstrap complete');
  }
}
