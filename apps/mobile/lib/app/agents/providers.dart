/// Riverpod composition for app-owned cross-domain agents.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/agents/agent.dart';
import '../../core/ai/agents/agent_artifact.dart';
import '../../core/ai/agents/agent_run_store.dart';
import '../../core/ai/agents/agent_runner.dart';
import '../../core/ai/agents/agent_trigger.dart';
import '../../core/ai/agents/providers.dart' as agent_providers;
import '../../core/ai/attention/attention.dart';
import '../../core/ai/attention/background_safe_attention.dart';
import '../../core/ai/attention/providers.dart' as attention_providers;
import '../../core/ai/contracts/source_identity.dart';
import '../../core/auth/current_user.dart';
import '../../core/background/background_scheduler.dart';
import '../../core/background/providers.dart' as background_providers;
import '../../core/lifeos/life_context.dart';
import '../../core/lifeos/life_signal.dart';
import '../../core/notifications/notification_preferences.dart';
import '../../design_system/preferences/theme_preferences.dart';
import '../life_context_composition.dart';
import 'daily_navigator_agent.dart';
import 'daily_navigator_synthesizer.dart';

final dailyNavigatorAgentProvider = Provider<DailyNavigatorAgent>(
  (ref) => const DailyNavigatorAgent(),
);

final latestDailyNavigatorArtifactProvider =
    FutureProvider.autoDispose<AgentArtifact?>((ref) async {
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final store = await ref.watch(
        agent_providers.agentArtifactStoreProvider.future,
      );
      final artifacts = await store.latestForAgent(
        ownerUserId: ownerUserId,
        agentId: kDailyNavigatorAgentId,
        limit: 1,
      );
      return artifacts.isEmpty ? null : artifacts.first;
    });

final dailyNavigatorTriggerCoordinatorProvider =
    Provider<AgentTriggerCoordinator>((ref) {
      final coordinator = AgentTriggerCoordinator(
        dispatch: (agentId, trigger, _) {
          if (agentId != kDailyNavigatorAgentId) {
            throw StateError('Unsupported app Agent trigger: $agentId');
          }
          return runDailyNavigator(ref, trigger: trigger);
        },
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

final dailyNavigatorTriggeredRunProvider =
    FutureProvider.autoDispose<AgentRunResult?>((ref) async {
      final context = await ref.watch(lifeContextSnapshotProvider.future);
      await _persistBackgroundSafeSnapshot(ref, context);
      return ref
          .watch(dailyNavigatorTriggerCoordinatorProvider)
          .submit(
            agentId: kDailyNavigatorAgentId,
            spec: const AgentTriggerSpec.event(
              id: 'life_context_changed',
              sourceFamily: 'life:context',
              debounce: Duration(milliseconds: 300),
            ),
            signal: AgentTriggerSignal(
              kind: AgentTriggerKind.event,
              key: 'active_life_context',
              observedAt: context.generatedAt,
              fingerprint: context.fingerprint,
              source: SourceIdentity.infrastructure(
                rowFamily: 'life:context',
                rowId: context.ownerUserId,
                fingerprint: context.fingerprint,
              ),
            ),
          );
    });

/// Keeps signal-driven Life synthesis mounted after authentication.
final lifeIntelligenceBootstrapProvider = Provider<void>((ref) {
  ref.watch(dailyNavigatorTriggeredRunProvider);
  ref.watch(lifeAttentionCronProvider);
  ref.watch(pendingBackgroundAttentionImportProvider);
});

final lifeAttentionCronProvider = Provider<void>((ref) {
  final scheduler = ref.watch(background_providers.backgroundSchedulerProvider);
  final enabled = ref.watch(notificationsEnabledProvider);
  unawaited(() async {
    if (!await scheduler.isAvailable()) return;
    if (enabled) {
      await scheduler.registerTask(kLifeAttentionBackgroundTask);
    } else {
      await scheduler.cancelTask(kLifeAttentionBackgroundTask);
    }
  }());
});

final pendingBackgroundAttentionImportProvider = FutureProvider<void>((
  ref,
) async {
  final store = SharedPreferencesBackgroundSafeAttentionStore(
    ref.watch(sharedPreferencesProvider),
  );
  final encoded = store.readPendingJson();
  if (encoded == null) return;
  try {
    final decision = AttentionDecision.fromJson(
      (jsonDecode(encoded) as Map).cast<String, Object?>(),
    );
    final decisionStore = await ref.read(
      attention_providers.attentionDecisionStoreProvider.future,
    );
    await decisionStore.save(decision);
  } finally {
    await store.clearPending();
  }
});

Future<AgentRunResult> runDailyNavigator(
  Ref ref, {
  DateTime? now,
  AgentRunTrigger trigger = AgentRunTrigger.manual,
}) async {
  final runner = await ref.read(agentRunnerProvider.future);
  final result = await runner.runOnce(
    ref.read(dailyNavigatorAgentProvider),
    AgentContext(ref: ref, now: (now ?? DateTime.now()).toUtc()),
    trigger: trigger,
  );
  ref.invalidate(latestDailyNavigatorArtifactProvider);
  return result;
}

Future<void> _persistBackgroundSafeSnapshot(
  Ref ref,
  LifeContextSnapshot context,
) async {
  final ownerUserId = await ref.read(currentUserIdProvider)();
  final decision = evaluateDailyNavigatorContext(context);
  final notificationsAllowed = ref.read(notificationsEnabledProvider);
  final attentionStore = await ref.read(
    attention_providers.attentionDecisionStoreProvider.future,
  );
  final recentInterruptCount = await attentionStore.recentInterruptCount(
    ownerUserId: ownerUserId,
    since: context.generatedAt.subtract(const Duration(hours: 24)),
  );
  final candidates = <AttentionCandidate>[
    for (final signal in decision?.signals ?? const <LifeEvent>[])
      AttentionCandidate(
        id: '$kDailyNavigatorFindingId:${signal.id}',
        agentId: kDailyNavigatorAgentId,
        findingFingerprint: '${context.fingerprint}:${signal.id}',
        severity:
            signal.template == LifeEventTemplate.recoveryAlert ||
                signal.template == LifeEventTemplate.executionBlocked
            ? AgentArtifactSeverity.warning
            : AgentArtifactSeverity.attention,
        confidence: 0.85,
        actionable: signal.routePath != null,
        fresh: true,
        evidenceComplete: signal.evidence.isNotEmpty,
        observedAt: context.generatedAt,
      ),
  ];
  await SharedPreferencesBackgroundSafeAttentionStore(
    ref.read(sharedPreferencesProvider),
  ).saveSnapshot(
    BackgroundSafeLifeSnapshot(
      ownerUserId: ownerUserId,
      fingerprint: context.fingerprint,
      computedAt: context.generatedAt,
      notificationsAllowed: notificationsAllowed,
      recentInterruptCount: recentInterruptCount,
      candidates: List<AttentionCandidate>.unmodifiable(candidates),
    ),
  );
}
