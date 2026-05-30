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
import 'health/ai_tools/record_body_measurement_tool.dart';

/// All HealthOS device tools (mostly read-only; low-frequency body
/// measurements have an explicit one-tap write path).
const List<DeviceTool> kHealthDeviceTools = <DeviceTool>[
  GetRecentSleepSummaryTool(),
  GetHrvTrendTool(),
  GetActivitySummaryTool(),
  GetRecoverySignalTool(),
  RecordBodyMeasurementTool(),
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
      'record_body_measurement': ToolDescriptor(
        name: 'record_body_measurement',
        access: Access.propose,
        risk: RiskLevel.commit,
        requiresConfirmation: Confirmation.oneTap,
        allowedContextTier: BudgetTier.small,
        sideEffect: SideEffect.deviceLocalWrite,
        domain: kDomainHealth,
      ),
    };

/// HealthOS system-prompt block. Appended onto [kDeviceSystemPromptBase]
/// by `systemPromptBlocksProvider` only when the user has opted into
/// the Health domain (`domainOptInsProvider`).
const String kHealthSystemPromptBlock =
    '[HealthOS 域]\n'
    '- 读取工具:get_recent_sleep_summary / get_hrv_trend / get_activity_summary / get_recovery_signal。\n'
    '- 低频身体指标可以写入:当用户明确说「记录/录入/保存体重或体脂」且给出数值时,使用 record_body_measurement。体重单位 kg;体脂 value 传百分数,例如 18.5 表示 18.5%。不要写睡眠 / HRV / 活动数据。\n'
    '- 解读趋势时使用工具返回的实际数值；不要凭体感推断「最近睡得好不好」。\n'
    '- HRV / 恢复评分有窗口期，工具会返回 window_days；引用结论时一并说明窗口长度，便于用户判断信号强度。';
