/// KnowledgeOS device-tool aggregator (`docs/lifeos-shell.md` §7.1 +
/// `docs/knowledgeos-domain.md` §4).
///
/// Mirrors `health_ai_tools.dart`. Bootstrap concatenates this list
/// into the cross-domain `deviceToolsProvider` only when the user has
/// opted into the Knowledge domain (`domainOptInsProvider`).
library;

import '../core/ai/contracts/intent.dart' show RiskLevel, kDomainKnowledge;
import '../core/ai/contracts/privacy_budget.dart' show BudgetTier;
import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/runtime/device/tools/device_tool.dart';
import 'knowledge/ai_tools/list_due_reviews_tool.dart';
import 'knowledge/ai_tools/list_open_assumptions_tool.dart';
import 'knowledge/ai_tools/propose_concept_link_tool.dart';
import 'knowledge/ai_tools/propose_inbox_classification_tool.dart';
import 'knowledge/ai_tools/propose_inbox_tags_tool.dart';
import 'knowledge/ai_tools/propose_link_to_decision_tool.dart';
import 'knowledge/ai_tools/recall_decision_tool.dart';
import 'knowledge/ai_tools/search_notes_tool.dart';
import 'knowledge/ai_tools/summarize_topic_evolution_tool.dart';

/// All KnowledgeOS device tools. Read-only except for the four
/// `propose_*` tools, each of which returns a ProposalEnvelope and
/// never writes directly to the synced KnowledgeOS tables.
/// The `propose_inbox_*` trio additionally persists its envelope into
/// the local-only `knowledge_inbox_triage` side-table so the Review
/// tab "AI 建议" card can render it without a second round-trip
/// (`docs/knowledgeos-domain.md` §5 异步 triage flow).
const List<DeviceTool> kKnowledgeDeviceTools = <DeviceTool>[
  RecallDecisionTool(),
  ListOpenAssumptionsTool(),
  ListDueReviewsTool(),
  SearchNotesTool(),
  ProposeConceptLinkTool(),
  ProposeInboxClassificationTool(),
  ProposeInboxTagsTool(),
  ProposeLinkToDecisionTool(),
  SummarizeTopicEvolutionTool(),
];

/// KnowledgeOS device-tool descriptors. Co-located with
/// [kKnowledgeDeviceTools] — adding a Knowledge tool means one new
/// file under `features/knowledge/ai_tools/`, one new line in
/// [kKnowledgeDeviceTools], and one new entry here. Merged into
/// [allToolDescriptors] by the cross-domain catalog.
const Map<String, ToolDescriptor> kKnowledgeToolDescriptors =
    <String, ToolDescriptor>{
  'recall_decision': ToolDescriptor(
    name: 'recall_decision',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainKnowledge,
  ),
  'list_open_assumptions': ToolDescriptor(
    name: 'list_open_assumptions',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainKnowledge,
  ),
  'list_due_reviews': ToolDescriptor(
    name: 'list_due_reviews',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainKnowledge,
  ),
  'search_notes': ToolDescriptor(
    name: 'search_notes',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainKnowledge,
  ),
  'summarize_topic_evolution': ToolDescriptor(
    name: 'summarize_topic_evolution',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainKnowledge,
  ),
  'propose_concept_link': ToolDescriptor(
    name: 'propose_concept_link',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainKnowledge,
  ),
  'propose_inbox_classification': ToolDescriptor(
    name: 'propose_inbox_classification',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.small,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainKnowledge,
  ),
  'propose_inbox_tags': ToolDescriptor(
    name: 'propose_inbox_tags',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.small,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainKnowledge,
  ),
  'propose_link_to_decision': ToolDescriptor(
    name: 'propose_link_to_decision',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.small,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: kDomainKnowledge,
  ),
};

/// KnowledgeOS system-prompt block. Appended onto [kDeviceSystemPromptBase]
/// by `systemPromptBlocksProvider` only when the user has opted into
/// the Knowledge domain (`domainOptInsProvider`).
const String kKnowledgeSystemPromptBlock =
    '[KnowledgeOS 域]\n'
    '- 编辑知识库条目时调用 propose_* 工具，工具返回「待确认计划」：\n'
    '  • propose_inbox_classification / propose_inbox_tags / propose_link_to_decision（收件箱分诊与归档）\n'
    '  • propose_concept_link（在两个概念 / 笔记之间建立关联）\n'
    '- 用户问「我以前对 X 的判断是什么」时优先调用 recall_decision；不要凭记忆复述决策内容。\n'
    '- 跨主题演变 / 历史观点对比用 summarize_topic_evolution，时间线以工具返回为准。';
