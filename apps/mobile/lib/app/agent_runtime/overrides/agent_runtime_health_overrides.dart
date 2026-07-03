/// FRB-backed provider overrides for HealthOS agents.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:naviwealth/app/agent_runtime/bindings/agent_runtime_profile_turn_binding.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_plan_binding.dart';
import 'package:naviwealth/core/notifications/notification_preferences.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/notifications/providers.dart' as notif_providers;
import 'package:naviwealth/features/health/agents/briefing_synthesizer.dart';
import 'package:naviwealth/features/health/agents/morning_briefing_agent.dart';
import 'package:naviwealth/features/health/agents/recovery_alert_agent.dart';
import 'package:naviwealth/features/health/agents/weekly_summary_agent.dart';
import 'package:naviwealth/features/health/data/health_notification_preferences.dart';
import 'package:naviwealth/features/health/data/morning_briefing_preferences.dart';

List<Override> agentRuntimeHealthProviderOverrides() => <Override>[
  morningBriefingAgentProvider.overrideWith((ref) {
    final frbRuntime = agentRuntimeProfileTurnBinding(
      ref,
      agentId: 'morning_briefing',
      domain: 'health',
      surface: 'health_morning_briefing',
      resolveAvailability: false,
    )!;
    final notifier = _briefingNotificationService(ref);
    return MorningBriefingAgent(
      synthesizer: FrbBriefingSynthesizer(
        runtime: frbRuntime,
        fallback: const ProgrammaticBriefingSynthesizer(),
      ),
      notifier: notifier,
      hourLocal: ref.watch(morningBriefingHourProvider),
    );
  }),
  recoveryAlertAgentProvider.overrideWith((ref) {
    return RecoveryAlertAgent(
      notifier: _briefingNotificationService(ref),
      signalReader: FrbRecoveryAlertSignalReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kRecoveryAlertAgentId,
          domain: 'health',
          surface: 'health_recovery_alert',
        ),
      ),
    );
  }),
  weeklySummaryAgentProvider.overrideWith((ref) {
    return WeeklySummaryAgent(
      summaryReader: FrbWeeklySummaryReader(
        runtime: agentRuntimeToolPlanBinding(
          ref,
          agentId: kWeeklySummaryAgentId,
          domain: 'health',
          surface: 'health_weekly_summary',
        ),
      ),
    );
  }),
];

NotificationService? _briefingNotificationService(Ref ref) {
  final notificationsEnabled = ref.watch(notificationsEnabledProvider);
  final briefingNotificationsEnabled = ref.watch(
    healthBriefingNotificationsEnabledProvider,
  );
  return notificationsEnabled && briefingNotificationsEnabled
      ? ref.watch(notif_providers.notificationServiceProvider)
      : null;
}
