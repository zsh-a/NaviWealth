/// HealthOS device-tool aggregator (`docs/lifeos-shell.md` §7.1, D-2.4).
///
/// Mirrors `finance_ai_tools.dart`. Bootstrap concatenates this list
/// into the cross-domain `deviceToolsProvider` only when the user has
/// opted into the Health domain (`domainOptInsProvider`).
library;

import '../core/ai/contracts/intent.dart' show RiskLevel, kDomainHealth;
import '../core/ai/contracts/privacy_budget.dart' show BudgetTier;
import '../core/ai/contracts/tool_descriptor.dart';
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

/// HealthOS device-tool descriptors. Co-located with [kHealthDeviceTools]
/// — adding a Health tool means one new file under
/// `features/health/ai_tools/`, one new line in [kHealthDeviceTools],
/// and one new entry here. Merged into [allToolDescriptors] by the
/// cross-domain catalog.
const Map<String, ToolDescriptor> kHealthToolDescriptors =
    <String, ToolDescriptor>{
  'get_recent_sleep_summary': ToolDescriptor(
    name: 'get_recent_sleep_summary',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainHealth,
  ),
  'get_hrv_trend': ToolDescriptor(
    name: 'get_hrv_trend',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainHealth,
  ),
  'get_activity_summary': ToolDescriptor(
    name: 'get_activity_summary',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainHealth,
  ),
  'get_recovery_signal': ToolDescriptor(
    name: 'get_recovery_signal',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainHealth,
  ),
};

/// HealthOS system-prompt block. Appended onto [kDeviceSystemPromptBase]
/// by `systemPromptBlocksProvider` only when the user has opted into
/// the Health domain (`domainOptInsProvider`).
const String kHealthSystemPromptBlock =
    '[HealthOS 域]\n'
    '- 健康域当前只有读取工具（get_recent_sleep_summary / get_hrv_trend / get_activity_summary / get_recovery_signal），没有 propose_health_* 写工具——不要试图直接修改睡眠 / HRV / 活动数据。\n'
    '- 解读趋势时使用工具返回的实际数值；不要凭体感推断「最近睡得好不好」。\n'
    '- HRV / 恢复评分有窗口期，工具会返回 window_days；引用结论时一并说明窗口长度，便于用户判断信号强度。';
