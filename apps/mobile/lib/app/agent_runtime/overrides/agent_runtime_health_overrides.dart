/// FRB-backed provider overrides for HealthOS agents.
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/features/health/agents/recovery_alert_agent.dart';
import 'package:naviwealth/features/health/agents/weekly_summary_agent.dart';

List<Override> agentRuntimeHealthProviderOverrides() => <Override>[
  recoveryAlertAgentProvider.overrideWith((ref) {
    return RecoveryAlertAgent(
      signalReader: FrbRecoveryAlertSignalReader(
        runtime: agentRuntimeEffectPlanBinding(
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
        runtime: agentRuntimeEffectPlanBinding(
          ref,
          agentId: kWeeklySummaryAgentId,
          domain: 'health',
          surface: 'health_weekly_summary',
        ),
      ),
    );
  }),
];
