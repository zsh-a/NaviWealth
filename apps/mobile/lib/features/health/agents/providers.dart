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
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/background/background_scheduler.dart';
import '../../../core/background/providers.dart' as background_providers;
import '../../../design_system/preferences/theme_preferences.dart';
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
Future<AgentRunResult> runMorningBriefingNow(Ref ref) async {
  final runner = await ref.watch(agentRunnerProvider.future);
  final agent = ref.read(morningBriefingAgentProvider);
  return runner.runOnce(
    agent,
    AgentContext(ref: ref, now: DateTime.now().toUtc()),
  );
}
