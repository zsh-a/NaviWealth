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
      await scheduler.registerTask(kMorningBriefingBackgroundTask);
      await scheduler.registerTask(kKnowledgeRoutineDueBackgroundTask);
      await scheduler.registerTask(kExecutionReviewBackgroundTask);
      await scheduler.registerTask(kGarminSyncBackgroundTask);
      await scheduler.registerTask(kHealthPlatformSyncBackgroundTask);
      await scheduler.cancelTask(kMorningBriefingBackgroundTask);
      await scheduler.cancelTask(kKnowledgeRoutineDueBackgroundTask);
      await scheduler.cancelTask(kExecutionReviewBackgroundTask);
      await scheduler.cancelTask(kGarminSyncBackgroundTask);
      await scheduler.cancelTask(kHealthPlatformSyncBackgroundTask);
    },
    skip: Platform.isIOS || Platform.isAndroid
        ? 'Host-only provider safety check.'
        : false,
  );
}
