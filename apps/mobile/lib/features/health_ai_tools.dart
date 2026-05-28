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

/// HealthOS system-prompt block. Appended onto [kDeviceSystemPromptBase]
/// by `systemPromptBlocksProvider` only when the user has opted into
/// the Health domain (`domainOptInsProvider`).
const String kHealthSystemPromptBlock =
    '[HealthOS 域]\n'
    '- 健康域当前只有读取工具（get_recent_sleep_summary / get_hrv_trend / get_activity_summary / get_recovery_signal），没有 propose_health_* 写工具——不要试图直接修改睡眠 / HRV / 活动数据。\n'
    '- 解读趋势时使用工具返回的实际数值；不要凭体感推断「最近睡得好不好」。\n'
    '- HRV / 恢复评分有窗口期，工具会返回 window_days；引用结论时一并说明窗口长度，便于用户判断信号强度。';
