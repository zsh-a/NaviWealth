import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/logging/app_logger.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
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
