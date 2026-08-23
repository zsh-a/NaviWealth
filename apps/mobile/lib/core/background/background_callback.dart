/// Top-level workmanager dispatcher (`docs/architecture/lifeos-shell.md` §7.3,
/// D-2.5b).
///
/// Must be a top-level function with the `vm:entry-point` pragma so
/// AOT doesn't tree-shake it — `package:workmanager` invokes it by
/// name on the OS-scheduled wake-up. The function runs in a **fresh
/// isolate** with no Riverpod ProviderContainer, no Drift database,
/// and no AI runtime; we therefore keep the work minimal:
///
///   1. Stamp a task-specific SharedPreferences due key so the foreground
///      app sees there's pending work on next launch.
///   2. For Life attention only, inspect a precomputed primitive snapshot.
///      A persisted interrupt decision must exist before a notification posts.
///
/// Heavier "compute the briefing inside the background isolate"
/// is intentionally deferred — booting Drift + SQLCipher + Memory
/// Runtime inside the iOS BGTask 30s budget is fragile and would
/// regress reliability for marginal freshness. The foreground hook
/// in `app_dock_shell.dart` runs the actual agent.
library;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../ai/attention/background_safe_attention.dart';
import '../notifications/notification_service_factory.dart';
import 'background_scheduler.dart';

@pragma('vm:entry-point')
void lifeosBackgroundCallback() {
  Workmanager().executeTask((taskName, inputData) async {
    final task = backgroundTaskSpecForName(taskName);
    if (task == null) {
      return true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(
        task.dueAtPreferenceKey,
        now.toUtc().millisecondsSinceEpoch,
      );

      if (task.name == kLifeAttentionTaskName) {
        final store = SharedPreferencesBackgroundSafeAttentionStore(prefs);
        final snapshot = store.readSnapshot();
        final decision = snapshot == null
            ? null
            : const BackgroundSafeAttentionEvaluator().inspect(
                snapshot,
                now: now,
              );
        if (decision != null) {
          await store.savePending(decision);
          final notifier = createNotificationService();
          if (await notifier.hasPermissions()) {
            await notifier.showNow(
              id: lifeAttentionNotificationId(now),
              title: 'NaviWealth needs your attention',
              body: 'Open Daily Navigator to review the evidence.',
              channel: kLifeAttentionNotificationChannel,
              payload: '/life',
            );
          }
        }
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
