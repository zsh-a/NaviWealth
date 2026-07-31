/// HealthOS agent Riverpod wiring (D-2.5 + D-2.5b).
///
/// Three providers, each a side-effecting orchestration around the
/// shared agent runtime + platform scheduler. Kept in features/health/
/// instead of `core/ai/agents/` because the Morning Briefing is
/// HealthOS-specific.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_background_scheduler.dart';
import '../../../core/ai/agents/agent_presentation.dart';
import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart' as memory_providers;
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/background/background_scheduler.dart';
import '../../../core/background/providers.dart' as background_providers;
import '../../../core/notifications/notification_preferences.dart';
import '../../../design_system/preferences/theme_preferences.dart';
import '../data/health_notification_preferences.dart';
import '../data/health_sync_service.dart';
import '../data/providers.dart';
import 'morning_briefing_agent.dart';
import 'recovery_alert_agent.dart';

/// Shorter lookback for periodic foreground catch-up after a background wake.
/// Manual sync and Morning Briefing still use [kDefaultHealthSyncWindow].
const Duration kBackgroundHealthPlatformSyncWindow = Duration(days: 7);

/// D-2.5b side-effecting provider — watches the Health domain opt-in
/// and (re-)registers or cancels the workmanager periodic task that
/// wakes the Morning Briefing agent.
///
/// Plain (non-autoDispose) so it stays alive for the app lifetime;
/// bootstrap reads it once and every opt-in change rebuilds it.
final morningBriefingCronProvider = Provider<void>((ref) {
  final scheduler = ref.watch(background_providers.backgroundSchedulerProvider);
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  final healthEnabled = optIns?.contains(DomainScope.health) ?? false;
  final notificationsEnabled = ref.watch(notificationsEnabledProvider);
  final briefingEnabled = ref.watch(healthBriefingNotificationsEnabledProvider);
  ref.watch(agent_providers.agentPreferenceRevisionProvider);
  unawaited(() async {
    try {
      if (!await scheduler.isAvailable()) return;
      if (!healthEnabled || !notificationsEnabled || !briefingEnabled) {
        await scheduler.cancelTask(kMorningBriefingBackgroundTask);
        return;
      }
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final preferenceStore = await ref.read(
        agent_providers.agentPreferenceStoreProvider.future,
      );
      final agentEnabled = await preferenceStore.isEnabled(
        ownerUserId: ownerUserId,
        agentId: kMorningBriefingAgentId,
      );
      final agentNotificationsEnabled = await preferenceStore
          .areNotificationsEnabled(
            ownerUserId: ownerUserId,
            agentId: kMorningBriefingAgentId,
          );
      if (agentEnabled && agentNotificationsEnabled) {
        await scheduler.registerTask(kMorningBriefingBackgroundTask);
      } else {
        await scheduler.cancelTask(kMorningBriefingBackgroundTask);
      }
    } on Object {
      // Swallow — logging here would require dragging AppLogger into
      // every feature module. The scheduler impl is best-effort.
    }
  }());
});

/// Best-effort native background scheduler for Garmin sync. The workmanager
/// callback only stamps [kGarminSyncDueAtKey]; [pendingGarminSyncRunProvider]
/// performs the real sync in the foreground app process.
final garminSyncCronProvider = Provider<void>((ref) {
  final scheduler = ref.watch(background_providers.backgroundSchedulerProvider);
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  final healthEnabled = optIns?.contains(DomainScope.health) ?? false;
  final garminConnected =
      ref.watch(garminSyncControllerProvider) is GarminConnected;
  unawaited(() async {
    try {
      if (!await scheduler.isAvailable()) return;
      if (healthEnabled && garminConnected) {
        await scheduler.registerTask(kGarminSyncBackgroundTask);
      } else {
        await scheduler.cancelTask(kGarminSyncBackgroundTask);
      }
    } on Object {
      // Best-effort scheduler plumbing; foreground manual sync remains.
    }
  }());
});

/// Best-effort native background scheduler for HealthKit / Health Connect
/// sync. The workmanager callback only stamps [kHealthPlatformSyncDueAtKey];
/// [pendingHealthPlatformSyncRunProvider] performs the real platform/Drift
/// sync in the foreground app process.
final healthPlatformSyncCronProvider = Provider<void>((ref) {
  final scheduler = ref.watch(background_providers.backgroundSchedulerProvider);
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  final healthEnabled = optIns?.contains(DomainScope.health) ?? false;
  unawaited(() async {
    try {
      if (!await scheduler.isAvailable()) return;
      if (healthEnabled) {
        await scheduler.registerTask(kHealthPlatformSyncBackgroundTask);
      } else {
        await scheduler.cancelTask(kHealthPlatformSyncBackgroundTask);
      }
    } on Object {
      // Best-effort scheduler plumbing; foreground manual sync remains.
    }
  }());
});

/// D-2.5b — runs the Morning Briefing agent inside the app process if
/// the workmanager callback stamped [kMorningBriefingDueAtKey] while
/// the app was backgrounded. Returns the [AgentRunResult] (or `null`
/// when no pending flag was set). Bootstrap reads it on cold start.
final pendingBriefingRunProvider = FutureProvider.autoDispose<AgentRunResult?>((
  ref,
) async {
  final optIns = await ref.read(core_auth.domainOptInsProvider.future);
  if (!optIns.contains(DomainScope.health)) return null;
  return runDueMorningBriefingTick(ref);
});

/// Runs a pending Garmin sync after a native background wake-up stamped
/// [kGarminSyncDueAtKey]. The Rust bridge, secure token store, and Drift
/// writes stay in the foreground process instead of the background isolate.
final pendingGarminSyncRunProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  final link = ref.keepAlive();
  try {
    final optIns = await ref.read(core_auth.domainOptInsProvider.future);
    if (!optIns.contains(DomainScope.health)) return;
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    final due = prefs.getInt(kGarminSyncDueAtKey);
    if (due == null) return;
    await prefs.remove(kGarminSyncDueAtKey);
    await ref.read(garminSyncControllerProvider.notifier).syncNow();
  } finally {
    link.close();
  }
});

/// Runs a pending HealthKit / Health Connect sync after a native background
/// wake-up stamped [kHealthPlatformSyncDueAtKey]. The workmanager callback
/// cannot touch Drift, Riverpod, or platform auth safely, so the foreground
/// process owns the real sync.
final pendingHealthPlatformSyncRunProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  final link = ref.keepAlive();
  try {
    final optIns = await ref.read(core_auth.domainOptInsProvider.future);
    if (!optIns.contains(DomainScope.health)) return;
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    final due = prefs.getInt(kHealthPlatformSyncDueAtKey);
    if (due == null) return;
    await prefs.remove(kHealthPlatformSyncDueAtKey);
    final service = await ref.read(healthSyncServiceProvider.future);
    await service.syncRange(window: kBackgroundHealthPlatformSyncWindow);
  } finally {
    link.close();
  }
});

/// D-2.5b — manual one-shot trigger backing the Settings "Run morning
/// briefing now" button. Separate provider so the UI button doesn't
/// race the background-pending detection (each has its own autoDispose
/// lifecycle).
final manualMorningBriefingRunProvider =
    FutureProvider.autoDispose<AgentRunResult>((ref) async {
      return runMorningBriefingNow(ref);
    });

/// Background catch-up path used by [pendingBriefingRunProvider].
///
/// The OS background callback only marks a due flag. Foreground catch-up then
/// calls the shared scheduled-agent [AgentRunController.tick] entry so
/// [AgentSchedule] remains the only due/not-due policy.
Future<AgentRunResult?> runDueMorningBriefingTick(Ref ref) async {
  final link = ref.keepAlive();
  try {
    final catchUp = await ref.read(agentBackgroundCatchUpRunnerProvider.future);
    return catchUp.runIfDue(
      binding: const AgentBackgroundTaskBinding(
        agentId: kMorningBriefingAgentId,
        domain: DomainScope.health,
        task: kMorningBriefingBackgroundTask,
      ),
      beforeRun: () => _syncHealthBeforeBriefing(ref),
    );
  } finally {
    link.close();
  }
}

/// Explicit run-now path used by [manualMorningBriefingRunProvider].
/// Public so test scaffolds can drive the agent without going through
/// workmanager.
///
/// **Pulls every connected source first** so the briefing reflects last
/// night's sleep / HRV that the workmanager wakeup couldn't fetch from
/// the background isolate (Drift + SQLCipher would be expensive there).
/// Sync errors are swallowed — a stale snapshot is better than no
/// briefing.
Future<AgentRunResult> runMorningBriefingNow(Ref ref) async {
  // The agent run is long-lived (a platform sync + an LLM call) and the
  // calling providers are autoDispose, triggered via `ref.refresh(...future)`
  // which retains no subscription. Without this the provider can be torn
  // down mid-run and the resumed continuation (here and inside the agent,
  // which holds `ctx.ref`) touches a disposed Ref → "Cannot use the Ref of
  // FutureProvider<AgentRunResult> after it has been disposed". keepAlive
  // pins it for the duration; the link is released once the run settles.
  final link = ref.keepAlive();
  try {
    await _syncHealthBeforeBriefing(ref);
    final controller = await ref.read(agentRunControllerProvider.future);
    return await controller.runOnceById(kMorningBriefingAgentId);
  } finally {
    link.close();
  }
}

Future<void> _syncHealthBeforeBriefing(Ref ref) async {
  // Best-effort sync so the agent reads the night that just happened,
  // regardless of whether it came from the system platform or Garmin.
  // Wrapped so a missing service / permissions / network error doesn't
  // block the briefing from running on whatever data is already in the
  // local DB.
  try {
    final coordinator = await ref.read(healthRefreshCoordinatorProvider.future);
    await coordinator.refreshConnectedSources();
  } on Object {
    // Best-effort — sync failure here surfaces in the next manual sync.
  }
}

/// Most recent `morning_briefing` memory record, or `null` when none
/// have been produced yet (or HealthOS is off). Used by the HealthOS
/// Today page to render the briefing card.
///
/// Re-fires whenever [manualMorningBriefingRunProvider] or
/// [pendingBriefingRunProvider] complete so the card refreshes after a
/// run without a manual invalidate.
final latestMorningBriefingProvider = FutureProvider.autoDispose<MemoryRecord?>(
  (ref) async {
    final optIns = ref.watch(core_auth.domainOptInsProvider).value;
    if (optIns == null || !optIns.contains(DomainScope.health)) return null;
    // Re-run when a manual/pending briefing run completes so the
    // card picks up the new memory id without an extra refresh.
    ref.watch(manualMorningBriefingRunProvider);
    ref.watch(pendingBriefingRunProvider);
    final runtime = await ref.watch(
      memory_providers.memoryRuntimeProvider.future,
    );
    final ownerUserId = await ref.read(currentUserIdProvider)();
    final hits = await runtime.recall(
      ownerUserId: ownerUserId,
      source: kMorningBriefingMemorySource,
      kinds: const <MemoryKind>{MemoryKind.episodic},
      topK: 1,
    );
    if (hits.isEmpty) return null;
    return hits.first.record;
  },
);

/// Most recent user-visible Morning Briefing artifact. This is the unified
/// agent-result surface backing; the legacy memory provider remains for the
/// existing Health Today card until the UI migrates to artifact rendering.
final latestMorningBriefingArtifactProvider =
    FutureProvider.autoDispose<AgentArtifact?>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) return null;
      ref.watch(manualMorningBriefingRunProvider);
      ref.watch(pendingBriefingRunProvider);
      final store = await ref.watch(
        agent_providers.agentArtifactStoreProvider.future,
      );
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final artifacts = await store.latestForAgent(
        ownerUserId: ownerUserId,
        agentId: kMorningBriefingAgentId,
        limit: 1,
      );
      return artifacts.isEmpty ? null : artifacts.single;
    });

/// Most recent user-visible Recovery Alert artifact for Health Today.
final latestRecoveryAlertArtifactProvider =
    FutureProvider.autoDispose<AgentArtifact?>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) return null;
      final store = await ref.watch(
        agent_providers.agentArtifactStoreProvider.future,
      );
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final artifacts = await store.latestForAgent(
        ownerUserId: ownerUserId,
        agentId: kRecoveryAlertAgentId,
        limit: 1,
      );
      return artifacts.isEmpty ? null : artifacts.single;
    });

final latestRecoveryAlertRunProvider =
    FutureProvider.autoDispose<AgentRunRecord?>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) return null;
      final store = await ref.watch(
        agent_providers.agentRunStoreProvider.future,
      );
      final ownerUserId = await ref.read(currentUserIdProvider)();
      return store.latestForAgent(
        ownerUserId: ownerUserId,
        agentId: kRecoveryAlertAgentId,
      );
    });

const _healthReviewResultScope = agent_providers.AgentResultScope(
  domain: DomainScope.health,
  placement: AgentResultPlacement.domainReview,
  limit: 5,
);

final latestHealthReviewAgentResultsProvider =
    FutureProvider.autoDispose<agent_providers.AgentResultBundle>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) {
        return agent_providers.AgentResultBundle.empty;
      }
      return ref.watch(
        agent_providers
            .latestAgentResultsForPlacementProvider(_healthReviewResultScope)
            .future,
      );
    });

/// Most recent user-visible Weekly Summary artifact for the Health Today page.
final latestWeeklySummaryArtifactProvider =
    FutureProvider.autoDispose<AgentArtifact?>((ref) async {
      final bundle = await ref.watch(
        latestHealthReviewAgentResultsProvider.future,
      );
      return bundle.artifacts.isEmpty ? null : bundle.artifacts.first;
    });

/// Most recent Weekly Summary run status for Health Today fallback UI.
final latestWeeklySummaryRunProvider =
    FutureProvider.autoDispose<AgentRunRecord?>((ref) async {
      final bundle = await ref.watch(
        latestHealthReviewAgentResultsProvider.future,
      );
      return bundle.latestRun;
    });
