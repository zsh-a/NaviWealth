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
import '../../../core/ai/agents/agent_runner.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart' as memory_providers;
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/background/background_scheduler.dart';
import '../../../core/background/providers.dart' as background_providers;
import '../../../design_system/preferences/theme_preferences.dart';
import '../data/providers.dart';
import 'morning_briefing_agent.dart';

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
  unawaited(() async {
    try {
      if (!await scheduler.isAvailable()) return;
      if (healthEnabled) {
        await scheduler.registerMorningBriefing();
      } else {
        await scheduler.cancelMorningBriefing();
      }
    } on Object {
      // Swallow — logging here would require dragging AppLogger into
      // every feature module. The scheduler impl is best-effort.
    }
  }());
});

/// D-2.5b — runs the Morning Briefing agent inside the app process if
/// the workmanager callback stamped [kMorningBriefingDueAtKey] while
/// the app was backgrounded. Returns the [AgentRunResult] (or `null`
/// when no pending flag was set). Bootstrap reads it on cold start.
final pendingBriefingRunProvider =
    FutureProvider.autoDispose<AgentRunResult?>((ref) async {
      final optIns = ref.read(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) return null;
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      final due = prefs.getInt(kMorningBriefingDueAtKey);
      if (due == null) return null;
      await prefs.remove(kMorningBriefingDueAtKey);
      return runMorningBriefingNow(ref);
    });

/// D-2.5b — manual one-shot trigger backing the Settings "Run morning
/// briefing now" button. Separate provider so the UI button doesn't
/// race the background-pending detection (each has its own autoDispose
/// lifecycle).
final manualMorningBriefingRunProvider =
    FutureProvider.autoDispose<AgentRunResult>((ref) async {
      return runMorningBriefingNow(ref);
    });

/// Shared run-now path used by both [pendingBriefingRunProvider] and
/// [manualMorningBriefingRunProvider]. Public so test scaffolds can
/// drive the agent without going through workmanager.
///
/// **Pulls fresh platform data first** so the briefing reflects last
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
    // Best-effort sync so the agent reads the night that just happened.
    // Wrapped so a missing service / permissions / network error doesn't
    // block the briefing from running on whatever data is already in the
    // local DB.
    try {
      final svc = await ref.read(healthSyncServiceProvider.future);
      await svc.syncRange();
    } on Object {
      // Best-effort — sync failure here surfaces in the next manual sync.
    }
    // `read`, not `watch`: watching after an async gap re-subscribes the
    // already-running provider and can re-invalidate it mid-flight.
    final runner = await ref.read(agentRunnerProvider.future);
    final agent = ref.read(morningBriefingAgentProvider);
    return await runner.runOnce(
      agent,
      AgentContext(ref: ref, now: DateTime.now().toUtc()),
    );
  } finally {
    link.close();
  }
}

/// Most recent `morning_briefing` memory record, or `null` when none
/// have been produced yet (or HealthOS is off). Used by the HealthOS
/// Today page to render the briefing card.
///
/// Re-fires whenever [manualMorningBriefingRunProvider] or
/// [pendingBriefingRunProvider] complete so the card refreshes after a
/// run without a manual invalidate.
final latestMorningBriefingProvider =
    FutureProvider.autoDispose<MemoryRecord?>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) return null;
      // Re-run when a manual/pending briefing run completes so the
      // card picks up the new memory id without an extra refresh.
      ref.watch(manualMorningBriefingRunProvider);
      ref.watch(pendingBriefingRunProvider);
      final runtime = await ref.watch(memory_providers.memoryRuntimeProvider.future);
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final hits = await runtime.recall(
        ownerUserId: ownerUserId,
        source: kMorningBriefingMemorySource,
        kinds: const <MemoryKind>{MemoryKind.episodic},
        topK: 1,
      );
      if (hits.isEmpty) return null;
      return hits.first.record;
    });
