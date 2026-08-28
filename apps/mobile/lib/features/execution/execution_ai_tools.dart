/// ExecutionOS device-tool aggregator.
library;

import '../../core/ai/contracts/intent.dart' show RiskLevel, kDomainExecution;
import '../../core/ai/contracts/privacy_budget.dart' show BudgetTier;
import '../../core/ai/contracts/tool_descriptor.dart';
import '../../core/ai/runtime/device/tools/device_tool.dart';
import '../../core/ai/runtime/device/tools/registered_device_tool.dart';
import 'ai_tools/list_blocked_actions_tool.dart';
import 'ai_tools/list_open_actions_tool.dart';
import 'ai_tools/propose_action_status_update_tool.dart';
import 'ai_tools/propose_action_tool.dart';
import 'ai_tools/propose_commitment_tool.dart';
import 'ai_tools/propose_progress_tool.dart';
import 'ai_tools/propose_project_tool.dart';
import 'ai_tools/summarize_execution_progress_tool.dart';

const DeviceToolRegistrationBuilder _executionTool =
    DeviceToolRegistrationBuilder(kDomainExecution);

final List<RegisteredDeviceTool> kExecutionToolRegistrations =
    <RegisteredDeviceTool>[
      _executionTool.read(const ListOpenActionsTool()),
      _executionTool.read(const ListBlockedActionsTool()),
      _executionTool.read(
        const SummarizeExecutionProgressTool(),
        risk: RiskLevel.suggest,
        tier: BudgetTier.standard,
      ),
      _executionTool.propose(const ProposeActionTool()),
      _executionTool.propose(const ProposeActionStatusUpdateTool()),
      _executionTool.propose(const ProposeProjectTool()),
      _executionTool.propose(const ProposeCommitmentTool()),
      _executionTool.propose(const ProposeProgressTool()),
    ];

final List<DeviceTool> kExecutionDeviceTools = registeredDeviceTools(
  kExecutionToolRegistrations,
);

final Map<String, ToolDescriptor> kExecutionToolDescriptors =
    registeredToolDescriptors(kExecutionToolRegistrations);

const String kExecutionSystemPromptBlock =
    '[ExecutionOS 域]\n'
    '- 用户只需要理解 Action、Plan 和 Review：Action 是下一步要做的事，Plan 是一组相关行动，Review 用来复盘和调整。\n'
    '- Ongoing plan 是较长期的持续计划，ProgressEntry 只是内部兼容名；对用户统一称为 Update。\n'
    '- 查询当前待办用 list_open_actions；定位阻塞用 list_blocked_actions；复盘执行状态与 active Plan / Ongoing plan 上下文用 summarize_execution_progress。\n'
    '- 当 FinanceOS / HealthOS / KnowledgeOS 的洞察需要落地为执行对象时，优先创建 propose_action；只有明确需要多个步骤时才创建 propose_project，必要时再使用 propose_commitment / propose_progress。'
    '所有 propose_* 只返回待确认 proposal，不会直接写入。用户确认后才创建或记录。\n'
    '- 当用户要求完成、阻塞、恢复或放弃已有 Action 时，先用 list_open_actions 定位 action_id，再调用 propose_action_status_update 生成待确认状态更新。\n'
    '- 不要把 ExecutionOS 当团队项目管理工具；保持建议具体、可执行、下一步导向。';
