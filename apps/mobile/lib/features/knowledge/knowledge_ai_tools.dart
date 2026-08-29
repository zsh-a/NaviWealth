/// Focused KnowledgeOS device-tool catalog.
library;

import '../../core/ai/contracts/privacy_budget.dart' show BudgetTier;
import '../../core/ai/contracts/tool_descriptor.dart';
import '../../core/ai/runtime/device/tools/device_tool.dart';
import '../../core/ai/runtime/device/tools/registered_device_tool.dart';
import 'ai_tools/find_similar_knowledge_tool.dart';
import 'ai_tools/list_due_reviews_tool.dart';
import 'ai_tools/propose_capture_tool.dart';
import 'ai_tools/propose_merge_tool.dart';
import 'ai_tools/recall_decision_tool.dart';
import 'ai_tools/search_knowledge_tool.dart';
import 'ai_tools/search_notes_tool.dart';

const DeviceToolRegistrationBuilder _knowledgeTool =
    DeviceToolRegistrationBuilder('knowledge');

final List<RegisteredDeviceTool> kKnowledgeToolRegistrations =
    <RegisteredDeviceTool>[
      _knowledgeTool.read(const RecallDecisionTool()),
      _knowledgeTool.read(const ListDueReviewsTool()),
      _knowledgeTool.read(const SearchNotesTool()),
      _knowledgeTool.read(
        const SearchKnowledgeTool(),
        tier: BudgetTier.standard,
      ),
      _knowledgeTool.read(const FindSimilarKnowledgeTool()),
      _knowledgeTool.propose(const ProposeCaptureTool()),
      _knowledgeTool.propose(
        const ProposeMergeTool(),
        tier: BudgetTier.standard,
        visibleInAssistant: false,
      ),
    ];

final List<DeviceTool> kKnowledgeDeviceTools = registeredDeviceTools(
  kKnowledgeToolRegistrations,
);

final List<DeviceTool> kKnowledgeAssistantDeviceTools =
    registeredAssistantDeviceTools(kKnowledgeToolRegistrations);

final Map<String, ToolDescriptor> kKnowledgeToolDescriptors =
    registeredToolDescriptors(kKnowledgeToolRegistrations);

const String kKnowledgeSystemPromptBlock =
    '[KnowledgeOS 域]\n'
    '- Note 保存材料、观察和想法；Decision 保存已做出的选择、理由和复盘日期。\n'
    '- 录入使用 propose_capture，只有用户确认后才写入。\n'
    '- 搜索用 search_notes / search_knowledge，查重用 find_similar_knowledge。\n'
    '- 询问过去的判断时优先调用 recall_decision，不要凭记忆补全。';
