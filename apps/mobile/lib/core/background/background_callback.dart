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

import 'dart:ui' show Locale;

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../ai/agents/agent_l10n.dart';
import '../ai/attention/background_safe_attention.dart';
import '../config/app_config.dart';
import '../notifications/notification_preferences.dart';
import '../notifications/notification_service_factory.dart';
import '../update/native_update.dart';
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
      } else if (task.name == kNativeUpdateTaskName) {
        await _runNativeUpdateCheck(prefs);
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

Future<void> _runNativeUpdateCheck(SharedPreferences preferences) async {
  // WorkManager can also be configured by the shared iOS scheduler. The
  // update manifest is Android-specific, so never attempt a network request
  // or notification setup on another native platform.
  if (!isAndroidNativePlatform) return;

  final notifier = createNotificationService();
  const controller = NativeUpdateNotificationController();
  if (!(preferences.getBool(
        SharedBoolPreferenceController.notificationsEnabledKey,
      ) ??
      true)) {
    await controller.clear(notifier);
    return;
  }

  const config = AppConfig.dev;
  if (!config.hasNativeUpdateTarget) {
    await controller.clear(notifier);
    return;
  }

  final preferredLanguage = preferences.getString('naviwealth.locale');
  final l10n = defaultAgentL10n(
    preferredLanguage == null ? null : Locale(preferredLanguage),
  );
  final client = GitHubNativeUpdateClient();
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final result = await NativeUpdateChecker(
      config: config,
      packageInfo: packageInfo,
      preferences: preferences,
      client: client,
    ).check(forceRefresh: true);

    await controller.showIfNeeded(
      state: result.hasUpdate ? result.state : NativeUpdateState.hidden,
      service: notifier,
      preferences: preferences,
      title: l10n.nativeUpdateNotificationTitle,
      body: result.hasUpdate
          ? l10n.nativeUpdateNotificationBody(result.state.latestVersion)
          : '',
    );
  } finally {
    client.dispose();
  }
}
