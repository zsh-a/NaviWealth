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
  Future<void> registerMorningBriefing({
    Duration interval = const Duration(hours: 24),
  }) async {}

  @override
  Future<void> registerGarminSync({
    Duration interval = const Duration(hours: 6),
  }) async {}

  @override
  Future<void> registerHealthPlatformSync({
    Duration interval = const Duration(hours: 6),
  }) async {}

  @override
  Future<void> cancelMorningBriefing() async {}

  @override
  Future<void> cancelGarminSync() async {}

  @override
  Future<void> cancelHealthPlatformSync() async {}
}
