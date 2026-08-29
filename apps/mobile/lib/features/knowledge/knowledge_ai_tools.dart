/// KnowledgeOS device-tool aggregator (`docs/architecture/lifeos-shell.md` §7.1 +
/// `docs/domains/knowledgeos-domain.md` §4).
///
/// Mirrors `health_ai_tools.dart`. Bootstrap concatenates this list
/// into the cross-domain `deviceToolsProvider` only when the user has
/// opted into the Knowledge domain (`domainOptInsProvider`).
library;

import '../../core/ai/contracts/intent.dart' show RiskLevel, kDomainKnowledge;
import '../../core/ai/contracts/privacy_budget.dart' show BudgetTier;
import '../../core/ai/contracts/tool_descriptor.dart';
import '../../core/ai/runtime/device/tools/device_tool.dart';
import '../../core/ai/runtime/device/tools/registered_device_tool.dart';
import 'ai_tools/find_similar_knowledge_tool.dart';
import 'ai_tools/list_active_principles_tool.dart';
import 'ai_tools/list_due_reviews_tool.dart';
import 'ai_tools/list_due_routines_tool.dart';
import 'ai_tools/list_inbox_triage_candidates_tool.dart';
import 'ai_tools/list_open_assumptions_tool.dart';
import 'ai_tools/list_triage_decisions_tool.dart';
import 'ai_tools/propose_capture_tool.dart';
import 'ai_tools/propose_concept_link_tool.dart';
import 'ai_tools/propose_merge_tool.dart';
import 'ai_tools/propose_routine_tool.dart';
import 'ai_tools/queue_inbox_classification_tool.dart';
import 'ai_tools/queue_inbox_tags_tool.dart';
import 'ai_tools/queue_link_to_decision_tool.dart';
import 'ai_tools/recall_decision_tool.dart';
import 'ai_tools/review_knowledge_health_tool.dart';
import 'ai_tools/search_knowledge_tool.dart';
import 'ai_tools/search_notes_tool.dart';
import 'ai_tools/summarize_topic_evolution_tool.dart';

/// KnowledgeOS device tools and policy metadata. Read-only except for the
/// `propose_*` registrations, each of which returns a ProposalEnvelope and
/// never writes directly to the synced KnowledgeOS tables.
/// The `queue_inbox_*` trio additionally persists its envelope into
/// the local-only `knowledge_inbox_triage` side-table so the Review
/// tab "AI 建议" card can render it without a second round-trip
/// (`docs/domains/knowledgeos-domain.md` §5 异步 triage flow).
const DeviceToolRegistrationBuilder _knowledgeTool =
    DeviceToolRegistrationBuilder(kDomainKnowledge);

final List<RegisteredDeviceTool>
kKnowledgeToolRegistrations = <RegisteredDeviceTool>[
  _knowledgeTool.read(const RecallDecisionTool()),
  _knowledgeTool.read(
    const ListActivePrinciplesTool(),
    visibleInAssistant: false,
  ),
  _knowledgeTool.read(
    const ListOpenAssumptionsTool(),
    visibleInAssistant: false,
  ),
  _knowledgeTool.read(const ListDueReviewsTool()),
  _knowledgeTool.read(const ListDueRoutinesTool(), visibleInAssistant: false),
  _knowledgeTool.read(
    const ListInboxTriageCandidatesTool(),
    visibleInAssistant: false,
  ),
  _knowledgeTool.read(
    const ListTriageDecisionsTool(),
    visibleInAssistant: false,
  ),
  _knowledgeTool.read(const SearchNotesTool()),
  _knowledgeTool.read(const SearchKnowledgeTool(), tier: BudgetTier.standard),
  _knowledgeTool.read(const FindSimilarKnowledgeTool()),
  _knowledgeTool.read(
    const ReviewKnowledgeHealthTool(),
    tier: BudgetTier.standard,
  ),
  _knowledgeTool.propose(
    const ProposeConceptLinkTool(),
    tier: BudgetTier.standard,
    visibleInAssistant: false,
  ),
  _knowledgeTool.propose(
    const ProposeMergeTool(),
    tier: BudgetTier.standard,
    visibleInAssistant: false,
  ),
  _knowledgeTool.propose(
    const QueueInboxClassificationTool(),
    visibleInAssistant: false,
  ),
  _knowledgeTool.propose(const QueueInboxTagsTool(), visibleInAssistant: false),
  _knowledgeTool.propose(
    const QueueLinkToDecisionTool(),
    visibleInAssistant: false,
  ),
  _knowledgeTool.propose(const ProposeRoutineTool(), visibleInAssistant: false),
  _knowledgeTool.propose(const ProposeCaptureTool()),
  _knowledgeTool.read(
    const SummarizeTopicEvolutionTool(),
    risk: RiskLevel.suggest,
    tier: BudgetTier.standard,
  ),
];

final List<DeviceTool> kKnowledgeDeviceTools = registeredDeviceTools(
  kKnowledgeToolRegistrations,
);

final List<DeviceTool> kKnowledgeAssistantDeviceTools =
    registeredAssistantDeviceTools(kKnowledgeToolRegistrations);

final Map<String, ToolDescriptor> kKnowledgeToolDescriptors =
    registeredToolDescriptors(kKnowledgeToolRegistrations);

/// KnowledgeOS system-prompt block. Appended onto [kDeviceSystemPromptBase]
/// by `systemPromptBlocksProvider` only when the user has opted into
/// the Knowledge domain (`domainOptInsProvider`).
const String kKnowledgeSystemPromptBlock =
    '[KnowledgeOS 域]\n'
    '- 用户只需要理解 Note 与 Decision：Note 保存材料和想法，Decision 保存已经做出的判断及复盘日期。\n'
    '- 录入时使用 propose_capture；它只会建议保留为 Note 或升级为 Decision，且只返回待确认计划。\n'
    '- 查重先用 find_similar_knowledge；搜索历史内容用 search_notes / search_knowledge。旧版对象仍可被搜索，但不要主动要求用户选择底层对象类型。\n'
    '- 用户问「给我点建议 / 本周该做什么 / 知识库健康吗」时调用 review_knowledge_health，'
    '它汇总到期复盘 / 待确认建议 / 知识冲突 / 孤儿笔记。需要周期执行的事项交给 ExecutionOS。\n'
    '- 用户问「我以前对 X 的判断是什么」时优先调用 recall_decision；不要凭记忆复述决策内容。\n'
    '- 跨主题演变 / 历史观点对比用 summarize_topic_evolution，时间线以工具返回为准。';
