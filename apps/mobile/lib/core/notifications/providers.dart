/// Riverpod wiring for [NotificationService]. Native targets get the
/// real `flutter_local_notifications` impl; web / desktop get the
/// not-supported stub via conditional import.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_service.dart';
import 'notification_service_factory.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => createNotificationService(),
);
