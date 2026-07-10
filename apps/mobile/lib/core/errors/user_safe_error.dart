import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';
import '../logging/app_logger.dart';

/// Marker for errors whose message was intentionally written for end users.
abstract interface class UserFacingError {
  String get userMessage;
}

/// Logs the technical error while returning a localized, non-sensitive copy.
///
/// UI error states should use this instead of interpolating arbitrary
/// exceptions, which can expose implementation details, credentials, paths,
/// or backend payloads.
String userSafeErrorMessage(
  BuildContext context,
  Object error, {
  StackTrace? stackTrace,
  String operation = 'ui operation',
}) {
  AppLogger.instance.w(
    '$operation failed',
    error: error,
    stackTrace: stackTrace,
  );
  if (error case final UserFacingError userFacing) {
    return userFacing.userMessage;
  }
  return AppLocalizations.of(context).commonSafeErrorMessage;
}
