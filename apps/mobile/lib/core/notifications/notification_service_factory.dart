/// Conditional-import factory for [NotificationService]. Native
/// targets get the real `flutter_local_notifications` impl; web /
/// desktop fall back to a not-supported stub.
library;

export 'notification_service_stub.dart'
    if (dart.library.io) 'notification_service_io.dart';
