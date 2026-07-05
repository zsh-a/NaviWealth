/// KnowledgeOS agent providers (`docs/domains/knowledgeos-domain.md` §7).
///
/// Bootstrap consumes [knowledgeAgentsProvider] and concatenates the
/// list into the global `agentRegistryProvider` when the user has
/// opted into the Knowledge domain.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_background_scheduler.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/background/background_scheduler.dart';
import '../../../core/background/providers.dart' as background_providers;
import '../../../core/notifications/notification_preferences.dart';
import '../../../core/notifications/providers.dart' as notif_providers;
import 'assumption_agent.dart';
import 'contradiction_agent.dart';
import 'inbox_triage_agent.dart';
import 'review_agent.dart';
import 'routine_due_agent.dart';

final reviewAgentProvider = Provider<ReviewAgent>((ref) => const ReviewAgent());

final assumptionAgentProvider = Provider<AssumptionAgent>(
  (ref) => const AssumptionAgent(),
);

final contradictionAgentProvider = Provider<ContradictionAgent>(
  (ref) => const ContradictionAgent(),
);

final inboxTriageAgentProvider = Provider<InboxTriageAgent>(
  (ref) => const InboxTriageAgent(),
);

/// RoutineDueAgent is wired with the shared notification service so the
/// daily run can post a local toast on the Knowledge Review channel. Bootstrap
/// may override this provider to route reads through the FRB runtime while
/// keeping the same Knowledge-local agent contract.
final routineDueAgentProvider = Provider<RoutineDueAgent>((ref) {
  final notificationsEnabled = ref.watch(notificationsEnabledProvider);
  final notifier = notificationsEnabled
      ? ref.watch(notif_providers.notificationServiceProvider)
      : null;
  return RoutineDueAgent(notifier: notifier);
});

/// Aggregated list — bootstrap composes this into the cross-domain
/// `agentRegistryProvider` only when Knowledge is opt-in.
final knowledgeAgentsProvider = Provider<List<Agent>>((ref) {
  return <Agent>[
    ref.watch(reviewAgentProvider),
    ref.watch(assumptionAgentProvider),
    ref.watch(contradictionAgentProvider),
    ref.watch(inboxTriageAgentProvider),
    ref.watch(routineDueAgentProvider),
  ];
});

/// Registers/cancels the KnowledgeOS routine-due background wake-up. The
/// callback only stamps [kKnowledgeRoutineDueAtKey]; foreground catch-up runs
/// the real agent through [AgentBackgroundCatchUpRunner].
final knowledgeRoutineDueCronProvider = Provider<void>((ref) {
  final scheduler = ref.watch(background_providers.backgroundSchedulerProvider);
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  final knowledgeEnabled = optIns?.contains(DomainScope.knowledge) ?? false;
  unawaited(() async {
    try {
      if (!await scheduler.isAvailable()) return;
      if (knowledgeEnabled) {
        await scheduler.registerTask(kKnowledgeRoutineDueBackgroundTask);
      } else {
        await scheduler.cancelTask(kKnowledgeRoutineDueBackgroundTask);
      }
    } on Object {
      // Best-effort scheduler plumbing. Foreground/manual review remains.
    }
  }());
});

final pendingKnowledgeRoutineDueRunProvider =
    FutureProvider.autoDispose<AgentRunResult?>((ref) async {
      final link = ref.keepAlive();
      try {
        final optIns = await ref.read(core_auth.domainOptInsProvider.future);
        if (!optIns.contains(DomainScope.knowledge)) return null;
        final catchUp = await ref.read(
          agentBackgroundCatchUpRunnerProvider.future,
        );
        return catchUp.runIfDue(
          binding: const AgentBackgroundTaskBinding(
            agentId: kKnowledgeRoutineAgentId,
            task: kKnowledgeRoutineDueBackgroundTask,
          ),
        );
      } finally {
        link.close();
      }
    });

/// Most recent user-visible Knowledge Review artifact for the Review tab.
final latestKnowledgeReviewArtifactProvider =
    FutureProvider.autoDispose<AgentArtifact?>((ref) async {
      final store = await ref.watch(
        agent_providers.agentArtifactStoreProvider.future,
      );
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final artifacts = await store.latestForAgent(
        ownerUserId: ownerUserId,
        agentId: kKnowledgeReviewAgentId,
        limit: 1,
      );
      return artifacts.isEmpty ? null : artifacts.single;
    });

final latestKnowledgeReviewRunProvider =
    FutureProvider.autoDispose<AgentRunRecord?>((ref) async {
      final store = await ref.watch(
        agent_providers.agentRunStoreProvider.future,
      );
      final ownerUserId = await ref.read(currentUserIdProvider)();
      return store.latestForAgent(
        ownerUserId: ownerUserId,
        agentId: kKnowledgeReviewAgentId,
      );
    });
