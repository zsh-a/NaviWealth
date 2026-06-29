/// KnowledgeOS device-tool aggregator (`docs/architecture/lifeos-shell.md` §7.1 +
/// `docs/domains/knowledgeos-domain.md` §4).
///
/// Mirrors `health_ai_tools.dart`. Bootstrap concatenates this list
/// into the cross-domain `deviceToolsProvider` only when the user has
/// opted into the Knowledge domain (`domainOptInsProvider`).
library;

import '../core/ai/contracts/intent.dart' show RiskLevel, kDomainKnowledge;
import '../core/ai/contracts/privacy_budget.dart' show BudgetTier;
import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/runtime/device/tools/device_tool.dart';
import '../core/ai/runtime/device/tools/registered_device_tool.dart';
import 'knowledge/ai_tools/find_similar_knowledge_tool.dart';
import 'knowledge/ai_tools/list_due_reviews_tool.dart';
import 'knowledge/ai_tools/list_due_routines_tool.dart';
import 'knowledge/ai_tools/list_inbox_triage_candidates_tool.dart';
import 'knowledge/ai_tools/list_open_assumptions_tool.dart';
import 'knowledge/ai_tools/list_triage_decisions_tool.dart';
import 'knowledge/ai_tools/propose_capture_tool.dart';
import 'knowledge/ai_tools/propose_concept_link_tool.dart';
import 'knowledge/ai_tools/propose_merge_tool.dart';
import 'knowledge/ai_tools/propose_routine_tool.dart';
import 'knowledge/ai_tools/queue_inbox_classification_tool.dart';
import 'knowledge/ai_tools/queue_inbox_tags_tool.dart';
import 'knowledge/ai_tools/queue_link_to_decision_tool.dart';
import 'knowledge/ai_tools/recall_decision_tool.dart';
import 'knowledge/ai_tools/review_knowledge_health_tool.dart';
import 'knowledge/ai_tools/search_knowledge_tool.dart';
import 'knowledge/ai_tools/search_notes_tool.dart';
import 'knowledge/ai_tools/summarize_topic_evolution_tool.dart';

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
  _knowledgeTool.read(const ListOpenAssumptionsTool()),
  _knowledgeTool.read(const ListDueReviewsTool()),
  _knowledgeTool.read(const ListDueRoutinesTool()),
  _knowledgeTool.read(const ListInboxTriageCandidatesTool()),
  _knowledgeTool.read(const ListTriageDecisionsTool()),
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
  ),
  _knowledgeTool.propose(const ProposeMergeTool(), tier: BudgetTier.standard),
  _knowledgeTool.propose(const QueueInboxClassificationTool()),
  _knowledgeTool.propose(const QueueInboxTagsTool()),
  _knowledgeTool.propose(const QueueLinkToDecisionTool()),
  _knowledgeTool.propose(const ProposeRoutineTool()),
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

final Map<String, ToolDescriptor> kKnowledgeToolDescriptors =
    registeredToolDescriptors(kKnowledgeToolRegistrations);

/// KnowledgeOS system-prompt block. Appended onto [kDeviceSystemPromptBase]
/// by `systemPromptBlocksProvider` only when the user has opted into
/// the Knowledge domain (`domainOptInsProvider`).
const String kKnowledgeSystemPromptBlock =
    '[KnowledgeOS 域]\n'
    '- 编辑知识库条目时调用 propose_* 工具，工具返回「待确认计划」：\n'
    '  • queue_inbox_classification / queue_inbox_tags / queue_link_to_decision（收件箱分诊与归档）\n'
    '  • propose_concept_link（在两个概念 / 笔记之间建立关联）\n'
    '  • propose_routine（用户表达「每 X 时间做一次 Y」/「需要定期活跃 / 续期 / 缴费」时调用，'
    'AI 选择合理 interval_days，由用户在 UI 一键确认）\n'
    '  • propose_capture（用户问「这条该归到哪里 / 是不是个 Routine」、'
    '或想让 AI 评估一段自由文本的合适落点时调用；kind == note 表示无需升级）\n'
    '  • propose_merge（去重：发现重复条目时建议合并，支持 note / concept / '
    'principle / assumption / decision / experiment；合并 assumption/principle/decision '
    '会自动重定向引用它们的决策与实验）\n'
    '- 录入 / 查重场景：先用 find_similar_knowledge 找近似条目；'
    'similarity ≥ 阈值说明可能重复，再用 propose_merge 建议合并（保留一条、其余软删）。\n'
    '- 跨类型检索「关于 X 我都记过什么 / 在哪写过」用 search_knowledge（笔记/概念/决策/原则/假设/实验一起搜）。\n'
    '- 用户问「给我点建议 / 本周该做什么 / 知识库健康吗」时调用 review_knowledge_health，'
    '它汇总到期复盘 / 本周到期定期事项 / 长期未校验假设 / 孤儿笔记，再据此用 propose_* 给出行动。\n'
    '- 用户问「我以前对 X 的判断是什么」时优先调用 recall_decision；不要凭记忆复述决策内容。\n'
    '- 跨主题演变 / 历史观点对比用 summarize_topic_evolution，时间线以工具返回为准。\n'
    '- 「我现在有什么定期事项要做 / 本周到期」用 list_due_routines，结合 list_due_reviews 给出综合提醒。';
