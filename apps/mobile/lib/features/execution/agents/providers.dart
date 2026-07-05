/// ExecutionOS agent providers.
///
/// Bootstrap consumes [executionAgentsProvider] through the Execution
/// DomainPack, so agents are registered only when Execution is active.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_background_scheduler.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/background/background_scheduler.dart';
import '../../../core/background/providers.dart' as background_providers;
import '../../../core/notifications/notification_preferences.dart';
import 'review_agent.dart';

final executionReviewAgentProvider = Provider<ExecutionReviewAgent>(
  (ref) => const ExecutionReviewAgent(),
);

final executionAgentsProvider = Provider<List<Agent>>((ref) {
  return <Agent>[ref.watch(executionReviewAgentProvider)];
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
      final agentNotificationsEnabled = await preferenceStore
          .areNotificationsEnabled(
            ownerUserId: ownerUserId,
            agentId: kExecutionReviewAgentId,
          );
      if (agentNotificationsEnabled) {
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
        return catchUp.runIfDue(
          binding: const AgentBackgroundTaskBinding(
            agentId: kExecutionReviewAgentId,
            task: kExecutionReviewBackgroundTask,
          ),
        );
      } finally {
        link.close();
      }
    });
