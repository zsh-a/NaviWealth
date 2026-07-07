/// Foreground catch-up helpers for background-capable agents.
///
/// The platform background isolate only stamps a SharedPreferences due flag.
/// Foreground code consumes that flag here, then runs the normal scheduled
/// [AgentRunController.tick] path with a `background_due` trigger.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import '../../auth/current_user.dart';
import '../../auth/domain_scope.dart';
import '../../auth/providers.dart' as auth_providers;
import '../../background/background_scheduler.dart';
import 'agent.dart';
import 'agent_preference_store.dart';
import 'agent_run_controller.dart';
import 'agent_run_store.dart';
import 'providers.dart' as agent_providers;

class AgentBackgroundTaskBinding {
  const AgentBackgroundTaskBinding({
    required this.agentId,
    required this.domain,
    required this.task,
  });

  final String agentId;
  final DomainScope domain;
  final BackgroundTaskSpec task;
}

class AgentDueFlagStore {
  const AgentDueFlagStore({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  DateTime? peekDue(BackgroundTaskSpec task) {
    final millis = _prefs.getInt(task.dueAtPreferenceKey);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  Future<DateTime?> consumeDue(BackgroundTaskSpec task) async {
    final dueAt = peekDue(task);
    if (dueAt == null) return null;
    await _prefs.remove(task.dueAtPreferenceKey);
    return dueAt;
  }
}

class AgentBackgroundCatchUpRunner {
  const AgentBackgroundCatchUpRunner({
    required AgentDueFlagStore dueFlags,
    required AgentPreferenceStore preferences,
    required AgentRunController controller,
    required Future<String> Function() currentUserId,
    required Future<DomainOptIns> Function() domainOptIns,
  }) : _dueFlags = dueFlags,
       _preferences = preferences,
       _controller = controller,
       _currentUserId = currentUserId,
       _domainOptIns = domainOptIns;

  final AgentDueFlagStore _dueFlags;
  final AgentPreferenceStore _preferences;
  final AgentRunController _controller;
  final Future<String> Function() _currentUserId;
  final Future<DomainOptIns> Function() _domainOptIns;

  Future<AgentRunResult?> runIfDue({
    required AgentBackgroundTaskBinding binding,
    Future<void> Function()? beforeRun,
  }) async {
    final dueAt = await _dueFlags.consumeDue(binding.task);
    if (dueAt == null) return null;
    final optIns = await _domainOptIns();
    if (!optIns.contains(binding.domain)) return null;
    final ownerUserId = await _currentUserId();
    final enabled = await _preferences.isEnabled(
      ownerUserId: ownerUserId,
      agentId: binding.agentId,
    );
    if (!enabled) return null;
    final results = await _controller.tick(
      now: dueAt,
      onlyAgentIds: <String>[binding.agentId],
      trigger: AgentRunTrigger.backgroundDue,
      beforeRun: beforeRun == null ? null : (_) => beforeRun(),
    );
    return results.isEmpty ? null : results.first;
  }
}

final agentDueFlagStoreProvider = Provider<AgentDueFlagStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AgentDueFlagStore(prefs: prefs);
});

final agentBackgroundCatchUpRunnerProvider =
    FutureProvider<AgentBackgroundCatchUpRunner>((ref) async {
      final preferences = await ref.watch(
        agent_providers.agentPreferenceStoreProvider.future,
      );
      final controller = await ref.watch(agentRunControllerProvider.future);
      return AgentBackgroundCatchUpRunner(
        dueFlags: ref.watch(agentDueFlagStoreProvider),
        preferences: preferences,
        controller: controller,
        currentUserId: ref.read(currentUserIdProvider),
        domainOptIns: () =>
            ref.read(auth_providers.domainOptInsProvider.future),
      );
    });
