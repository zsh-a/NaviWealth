import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/notifications/providers.dart';

void main() {
  test(
    'notificationServiceProvider exposes a safe service on host tests',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(notificationServiceProvider);

      expect(service, isA<NotificationService>());
      expect(await service.isAvailable(), isFalse);
      expect(await service.hasPermissions(), isFalse);
      expect(await service.requestPermissions(), isFalse);
      await service.showNow(
        id: 42,
        title: 'Title',
        body: 'Body',
        channel: _testChannel,
      );
      await service.cancel(42);
    },
    skip: Platform.isIOS || Platform.isAndroid
        ? 'Host-only provider safety check.'
        : false,
  );
}

const NotificationChannelSpec _testChannel = NotificationChannelSpec(
  id: 'lifeos.test',
  name: 'Test',
  description: 'Test notifications.',
);
