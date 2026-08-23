/// HealthOS Agent and background-sync Riverpod wiring.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_presentation.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/background/background_scheduler.dart';
import '../../../core/background/providers.dart' as background_providers;
import '../../../design_system/preferences/theme_preferences.dart';
import '../data/providers.dart';
import 'recovery_alert_agent.dart';

const Duration kBackgroundHealthPlatformSyncWindow = Duration(days: 7);

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

final latestWeeklySummaryArtifactProvider =
    FutureProvider.autoDispose<AgentArtifact?>((ref) async {
      final bundle = await ref.watch(
        latestHealthReviewAgentResultsProvider.future,
      );
      return bundle.artifacts.isEmpty ? null : bundle.artifacts.first;
    });

final latestWeeklySummaryRunProvider =
    FutureProvider.autoDispose<AgentRunRecord?>((ref) async {
      final bundle = await ref.watch(
        latestHealthReviewAgentResultsProvider.future,
      );
      return bundle.latestRun;
    });
