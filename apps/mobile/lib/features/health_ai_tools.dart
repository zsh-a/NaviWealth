/// HealthOS device-tool aggregator (`docs/lifeos-shell.md` §7.1, D-2.4).
///
/// Mirrors `finance_ai_tools.dart`. Bootstrap concatenates this list
/// into the cross-domain `deviceToolsProvider` only when the user has
/// opted into the Health domain (`domainOptInsProvider`).
library;

import '../core/ai/runtime/device/tools/device_tool.dart';
import 'health/ai_tools/get_activity_summary_tool.dart';
import 'health/ai_tools/get_hrv_trend_tool.dart';
import 'health/ai_tools/get_recent_sleep_summary_tool.dart';
import 'health/ai_tools/get_recovery_signal_tool.dart';

/// All HealthOS device tools (read-only, per `healthos-domain.md` §4).
const List<DeviceTool> kHealthDeviceTools = <DeviceTool>[
  GetRecentSleepSummaryTool(),
  GetHrvTrendTool(),
  GetActivitySummaryTool(),
  GetRecoverySignalTool(),
];
