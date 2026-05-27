/// Top-level workmanager dispatcher (`docs/lifeos-shell.md` §7.3,
/// D-2.5b).
///
/// Must be a top-level function with the `vm:entry-point` pragma so
/// AOT doesn't tree-shake it — `package:workmanager` invokes it by
/// name on the OS-scheduled wake-up. The function runs in a **fresh
/// isolate** with no Riverpod ProviderContainer, no Drift database,
/// and no AI runtime; we therefore keep the work minimal:
///
///   1. Stamp `kMorningBriefingDueAtKey` in SharedPreferences so the
///      foreground app sees there's a pending run on next launch.
///   2. Post a placeholder notification via [NotificationService] so
///      the user knows the briefing is ready (the actual summary is
///      filled in once the app foregrounds and the in-process agent
///      runs against the full data).
///
/// Heavier "compute the briefing inside the background isolate"
/// is intentionally deferred — booting Drift + SQLCipher + Memory
/// Runtime inside the iOS BGTask 30s budget is fragile and would
/// regress reliability for marginal freshness. The foreground hook
/// in `app_dock_shell.dart` runs the actual agent.
library;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../notifications/notification_service.dart';
import '../notifications/notification_service_factory.dart';
import 'background_scheduler.dart';

@pragma('vm:entry-point')
void lifeosBackgroundCallback() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kMorningBriefingTaskName) {
      return true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(
        kMorningBriefingDueAtKey,
        now.toUtc().millisecondsSinceEpoch,
      );

      final notifier = createNotificationService();
      if (await notifier.hasPermissions()) {
        await notifier.showNow(
          id: HealthNotifications.idForBriefing(now),
          title: 'Morning briefing ready',
          body: 'Open the app to see today\'s HealthOS summary.',
        );
      }
    } on Object {
      // Background-isolate failures aren't surfaced anywhere useful.
      // Returning `true` keeps WorkManager from marking the task as
      // failed and back-off-retrying immediately — we'll try again
      // next cycle.
    }
    return true;
  });
}
