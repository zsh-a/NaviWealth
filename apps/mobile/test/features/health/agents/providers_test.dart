import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/background/background_scheduler.dart';
import 'package:naviwealth/core/background/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/health/agents/morning_briefing_agent.dart';
import 'package:naviwealth/features/health/agents/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'morning briefing cron follows agent enabled and notification preferences',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final db = makeTestDatabase();
      addTearDown(db.close);
      final scheduler = _RecordingScheduler();
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          backgroundSchedulerProvider.overrideWithValue(scheduler),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
        ],
      );
      addTearDown(c.dispose);
      await c.read(auth.domainOptInsProvider.future);
      await c
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);

      final sub = c.listen<void>(
        morningBriefingCronProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await pumpEventQueue(times: 4);

      expect(scheduler.calls.last, 'register:$kMorningBriefingTaskName');

      final preferenceStore = await c.read(
        agent_providers.agentPreferenceStoreProvider.future,
      );
      await preferenceStore.setNotificationsEnabled(
        ownerUserId: 'user-1',
        agentId: kMorningBriefingAgentId,
        enabled: false,
        updatedAt: DateTime.utc(2026, 7, 5, 9),
      );
      final revision = c.read(
        agent_providers.agentPreferenceRevisionProvider.notifier,
      );
      revision.state = revision.state + 1;
      await pumpEventQueue(times: 4);

      expect(scheduler.calls.last, 'cancel:$kMorningBriefingTaskName');

      await preferenceStore.setNotificationsEnabled(
        ownerUserId: 'user-1',
        agentId: kMorningBriefingAgentId,
        enabled: true,
        updatedAt: DateTime.utc(2026, 7, 5, 10),
      );
      await preferenceStore.setEnabled(
        ownerUserId: 'user-1',
        agentId: kMorningBriefingAgentId,
        enabled: false,
        updatedAt: DateTime.utc(2026, 7, 5, 10),
      );
      revision.state = revision.state + 1;
      await pumpEventQueue(times: 4);

      expect(scheduler.calls.last, 'cancel:$kMorningBriefingTaskName');
    },
  );
}

class _RecordingScheduler implements BackgroundScheduler {
  final List<String> calls = <String>[];

  @override
  Future<void> cancelTask(BackgroundTaskSpec task) async {
    calls.add('cancel:${task.name}');
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> registerTask(
    BackgroundTaskSpec task, {
    Duration? interval,
  }) async {
    calls.add('register:${task.name}');
  }
}
