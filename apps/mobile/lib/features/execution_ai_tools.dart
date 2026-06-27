/// ExecutionOS device-tool aggregator.
library;

import '../core/ai/contracts/intent.dart' show RiskLevel, kDomainExecution;
import '../core/ai/contracts/privacy_budget.dart' show BudgetTier;
import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/runtime/device/tools/device_tool.dart';
import '../core/ai/runtime/device/tools/registered_device_tool.dart';
import 'execution/ai_tools/list_blocked_actions_tool.dart';
import 'execution/ai_tools/list_open_actions_tool.dart';
import 'execution/ai_tools/propose_action_tool.dart';
import 'execution/ai_tools/summarize_execution_progress_tool.dart';

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
    ];

final List<DeviceTool> kExecutionDeviceTools = registeredDeviceTools(
  kExecutionToolRegistrations,
);

final Map<String, ToolDescriptor> kExecutionToolDescriptors =
    registeredToolDescriptors(kExecutionToolRegistrations);

const String kExecutionSystemPromptBlock =
    '[ExecutionOS 域]\n'
    '- Action 是个人 todo / next action；Project 是有边界的交付容器；Commitment 是较长期承诺；ProgressEntry 是进展记录。\n'
    '- 查询当前待办用 list_open_actions；定位阻塞用 list_blocked_actions；复盘执行状态用 summarize_execution_progress。\n'
    '- 当 FinanceOS / HealthOS / KnowledgeOS 的洞察需要转成具体下一步时，调用 propose_action。'
    'propose_action 只返回待确认 proposal，不会直接写入。用户确认后才创建 Action。\n'
    '- 不要把 ExecutionOS 当团队项目管理工具；保持建议具体、可执行、下一步导向。';
