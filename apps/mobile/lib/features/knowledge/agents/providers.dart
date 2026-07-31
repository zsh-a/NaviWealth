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
import '../../../core/ai/agents/agent_presentation.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/background/background_scheduler.dart';
import '../../../core/background/providers.dart' as background_providers;
import '../../../core/notifications/notification_preferences.dart';
import '../../../core/notifications/providers.dart' as notif_providers;
import '../data/knowledge_review_preferences.dart';
import 'assumption_agent.dart';
import 'contradiction_agent.dart';
import 'inbox_triage_agent.dart';
import 'review_agent.dart';
import 'routine_due_agent.dart';

final reviewAgentProvider = Provider<ReviewAgent>((ref) {
  final preferences = ref.watch(knowledgeReviewPreferencesProvider);
  return ReviewAgent(
    reviewIntervalDays: preferences.cadenceDays,
    staleAssumptionDays: preferences.staleAssumptionDays,
  );
});

final assumptionAgentProvider = Provider<AssumptionAgent>(
  (ref) => AssumptionAgent(
    staleAssumptionDays: ref
        .watch(knowledgeReviewPreferencesProvider)
        .staleAssumptionDays,
  ),
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
  final notificationsEnabled = ref.watch(notificationsEnabledProvider);
  ref.watch(agent_providers.agentPreferenceRevisionProvider);
  unawaited(() async {
    try {
      if (!await scheduler.isAvailable()) return;
      if (!knowledgeEnabled || !notificationsEnabled) {
        await scheduler.cancelTask(kKnowledgeRoutineDueBackgroundTask);
        return;
      }
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final preferenceStore = await ref.read(
        agent_providers.agentPreferenceStoreProvider.future,
      );
      final agentEnabled = await preferenceStore.isEnabled(
        ownerUserId: ownerUserId,
        agentId: kKnowledgeRoutineAgentId,
      );
      final agentNotificationsEnabled = await preferenceStore
          .areNotificationsEnabled(
            ownerUserId: ownerUserId,
            agentId: kKnowledgeRoutineAgentId,
          );
      if (agentEnabled && agentNotificationsEnabled) {
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
            domain: DomainScope.knowledge,
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
      final bundle = await ref.watch(
        latestKnowledgeReviewResultsProvider.future,
      );
      return bundle.artifacts.isEmpty ? null : bundle.artifacts.first;
    });

/// Latest visible KnowledgeOS agent artifacts for the Review tab.
///
/// Knowledge contributes several review-placement agents (review, assumptions,
/// contradictions, inbox triage, routine due). The Review page renders this
/// list so all user-visible outputs share the same result card surface.
final latestKnowledgeReviewArtifactsProvider =
    FutureProvider.autoDispose<List<AgentArtifact>>((ref) async {
      final bundle = await ref.watch(
        latestKnowledgeReviewResultsProvider.future,
      );
      return bundle.artifacts;
    });

const _knowledgeReviewResultScope = agent_providers.AgentResultScope(
  domain: DomainScope.knowledge,
  placement: AgentResultPlacement.domainReview,
  limit: 5,
);

final latestKnowledgeReviewResultsProvider =
    FutureProvider.autoDispose<agent_providers.AgentResultBundle>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.knowledge)) {
        return agent_providers.AgentResultBundle.empty;
      }
      return ref.watch(
        agent_providers
            .latestAgentResultsForPlacementProvider(_knowledgeReviewResultScope)
            .future,
      );
    });

final latestKnowledgeReviewRunProvider =
    FutureProvider.autoDispose<AgentRunRecord?>((ref) async {
      final bundle = await ref.watch(
        latestKnowledgeReviewResultsProvider.future,
      );
      return bundle.latestRun;
    });
