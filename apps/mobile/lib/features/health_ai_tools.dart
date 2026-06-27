/// HealthOS device-tool aggregator (`docs/architecture/lifeos-shell.md` §7.1, D-2.4).
///
/// Mirrors `finance_ai_tools.dart`. Bootstrap concatenates this list
/// into the cross-domain `deviceToolsProvider` only when the user has
/// opted into the Health domain (`domainOptInsProvider`).
library;

import '../core/ai/contracts/intent.dart' show RiskLevel, kDomainHealth;
import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/runtime/device/tools/device_tool.dart';
import '../core/ai/runtime/device/tools/registered_device_tool.dart';
import 'health/ai_tools/get_activity_summary_tool.dart';
import 'health/ai_tools/get_body_battery_trend_tool.dart';
import 'health/ai_tools/get_hrv_trend_tool.dart';
import 'health/ai_tools/get_recent_sleep_summary_tool.dart';
import 'health/ai_tools/get_recovery_signal_tool.dart';
import 'health/ai_tools/get_stress_trend_tool.dart';
import 'health/ai_tools/record_body_measurement_tool.dart';

/// HealthOS device tools and policy metadata. Adding a Health tool means
/// adding one registration here; the runtime tool list and descriptor map
/// are derived below.
const DeviceToolRegistrationBuilder _healthTool = DeviceToolRegistrationBuilder(
  kDomainHealth,
);

final List<RegisteredDeviceTool> kHealthToolRegistrations =
    <RegisteredDeviceTool>[
      _healthTool.read(const GetRecentSleepSummaryTool()),
      _healthTool.read(const GetHrvTrendTool()),
      _healthTool.read(const GetStressTrendTool()),
      _healthTool.read(const GetBodyBatteryTrendTool()),
      _healthTool.read(const GetActivitySummaryTool()),
      _healthTool.read(const GetRecoverySignalTool(), risk: RiskLevel.suggest),
      _healthTool.propose(
        const RecordBodyMeasurementTool(),
        risk: RiskLevel.commit,
      ),
    ];

final List<DeviceTool> kHealthDeviceTools = registeredDeviceTools(
  kHealthToolRegistrations,
);

final Map<String, ToolDescriptor> kHealthToolDescriptors =
    registeredToolDescriptors(kHealthToolRegistrations);

/// HealthOS system-prompt block. Appended onto [kDeviceSystemPromptBase]
/// by `systemPromptBlocksProvider` only when the user has opted into
/// the Health domain (`domainOptInsProvider`).
const String kHealthSystemPromptBlock =
    '[HealthOS 域]\n'
    '- 读取工具:get_recent_sleep_summary / get_hrv_trend / get_stress_trend / get_body_battery_trend / get_activity_summary / get_recovery_signal。\n'
    '- 写入工具:record_body_measurement。只在用户明确要求记录体重或体脂并给出数值时使用,且需要用户确认。\n'
    '- 解读趋势时使用工具返回的实际数值；不要凭体感推断「最近睡得好不好」。\n'
    '- HRV / 压力 / Body Battery / 恢复评分有窗口期，工具会返回 window_days；引用结论时一并说明窗口长度，便于用户判断信号强度。\n'
    '- 压力和 Body Battery 是 Garmin 独有数据；如果用户未连接 Garmin，这些工具会返回空数据。';
