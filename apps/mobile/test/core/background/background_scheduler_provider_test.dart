import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/background/background_scheduler.dart';
import 'package:naviwealth/core/background/providers.dart';

void main() {
  test(
    'backgroundSchedulerProvider exposes a safe scheduler on host tests',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final scheduler = container.read(backgroundSchedulerProvider);

      expect(scheduler, isA<BackgroundScheduler>());
      expect(await scheduler.isAvailable(), isFalse);
      await scheduler.initialize();
      await scheduler.registerMorningBriefing();
      await scheduler.registerGarminSync();
      await scheduler.registerHealthPlatformSync();
      await scheduler.cancelMorningBriefing();
      await scheduler.cancelGarminSync();
      await scheduler.cancelHealthPlatformSync();
    },
    skip: Platform.isIOS || Platform.isAndroid
        ? 'Host-only provider safety check.'
        : false,
  );
}
