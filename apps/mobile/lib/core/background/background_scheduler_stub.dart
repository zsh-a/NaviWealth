/// Web / desktop fallback for [BackgroundScheduler]. Every method is
/// a safe no-op so the rest of the bootstrap can stay
/// platform-agnostic.
library;

import 'background_scheduler.dart';

BackgroundScheduler createBackgroundScheduler() =>
    const _UnsupportedBackgroundScheduler();

class _UnsupportedBackgroundScheduler implements BackgroundScheduler {
  const _UnsupportedBackgroundScheduler();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> registerTask(
    BackgroundTaskSpec task, {
    Duration? interval,
  }) async {}

  @override
  Future<void> cancelTask(BackgroundTaskSpec task) async {}
}
