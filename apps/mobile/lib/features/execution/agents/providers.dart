/// ExecutionOS agent providers.
///
/// Bootstrap consumes [executionAgentsProvider] through the Execution
/// DomainPack, so agents are registered only when Execution is active.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_background_scheduler.dart';
import '../../../core/ai/agents/agent_presentation.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/background/background_scheduler.dart';
import '../../../core/background/providers.dart' as background_providers;
import '../../../core/notifications/notification_preferences.dart';
import '../../../core/notifications/providers.dart' as notification_providers;
import 'due_action_agent.dart';
import 'review_agent.dart';

final executionReviewAgentProvider = Provider<ExecutionReviewAgent>(
  (ref) => const ExecutionReviewAgent(),
);

final executionDueActionAgentProvider = Provider<ExecutionDueActionAgent>((
  ref,
) {
  final notifier = ref.watch(notificationsEnabledProvider)
      ? ref.watch(notification_providers.notificationServiceProvider)
      : null;
  return ExecutionDueActionAgent(notifier: notifier);
});

final executionAgentsProvider = Provider<List<Agent>>((ref) {
  return <Agent>[
    ref.watch(executionReviewAgentProvider),
    ref.watch(executionDueActionAgentProvider),
  ];
});

const _executionReviewResultScope = agent_providers.AgentResultScope(
  domain: DomainScope.execution,
  placement: AgentResultPlacement.domainReview,
  limit: 5,
);

final latestExecutionReviewResultsProvider =
    FutureProvider.autoDispose<agent_providers.AgentResultBundle>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.execution)) {
        return agent_providers.AgentResultBundle.empty;
      }
      return ref.watch(
        agent_providers
            .latestAgentResultsForPlacementProvider(_executionReviewResultScope)
            .future,
      );
    });

final latestExecutionReviewArtifactProvider =
    FutureProvider.autoDispose<AgentArtifact?>((ref) async {
      final bundle = await ref.watch(
        latestExecutionReviewResultsProvider.future,
      );
      return bundle.artifacts.isEmpty ? null : bundle.artifacts.first;
    });

final latestExecutionReviewRunProvider =
    FutureProvider.autoDispose<AgentRunRecord?>((ref) async {
      final bundle = await ref.watch(
        latestExecutionReviewResultsProvider.future,
      );
      return bundle.latestRun;
    });

/// Registers/cancels the ExecutionOS review background wake-up. The native
/// callback stamps [kExecutionReviewDueAtKey]; foreground catch-up runs the
/// shared [AgentRunController] path via [AgentBackgroundCatchUpRunner].
final executionReviewCronProvider = Provider<void>((ref) {
  final scheduler = ref.watch(background_providers.backgroundSchedulerProvider);
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  final executionEnabled = optIns?.contains(DomainScope.execution) ?? false;
  final notificationsEnabled = ref.watch(notificationsEnabledProvider);
  ref.watch(agent_providers.agentPreferenceRevisionProvider);
  unawaited(() async {
    try {
      if (!await scheduler.isAvailable()) return;
      if (!executionEnabled || !notificationsEnabled) {
        await scheduler.cancelTask(kExecutionReviewBackgroundTask);
        return;
      }
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final preferenceStore = await ref.read(
        agent_providers.agentPreferenceStoreProvider.future,
      );
      final agentEnabled = await preferenceStore.isEnabled(
        ownerUserId: ownerUserId,
        agentId: kExecutionReviewAgentId,
      );
      final agentNotificationsEnabled = await preferenceStore
          .areNotificationsEnabled(
            ownerUserId: ownerUserId,
            agentId: kExecutionReviewAgentId,
          );
      if (agentEnabled && agentNotificationsEnabled) {
        await scheduler.registerTask(kExecutionReviewBackgroundTask);
      } else {
        await scheduler.cancelTask(kExecutionReviewBackgroundTask);
      }
    } on Object {
      // Best-effort scheduler plumbing. Foreground review remains available.
    }
  }());
});

final pendingExecutionReviewRunProvider =
    FutureProvider.autoDispose<AgentRunResult?>((ref) async {
      final link = ref.keepAlive();
      try {
        final optIns = await ref.read(core_auth.domainOptInsProvider.future);
        if (!optIns.contains(DomainScope.execution)) return null;
        final catchUp = await ref.read(
          agentBackgroundCatchUpRunnerProvider.future,
        );
        return await catchUp.runIfDue(
          binding: const AgentBackgroundTaskBinding(
            agentId: kExecutionReviewAgentId,
            domain: DomainScope.execution,
            task: kExecutionReviewBackgroundTask,
          ),
        );
      } finally {
        link.close();
      }
    });
