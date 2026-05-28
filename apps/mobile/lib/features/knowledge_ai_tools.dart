/// KnowledgeOS device-tool aggregator (`docs/lifeos-shell.md` §7.1 +
/// `docs/knowledgeos-domain.md` §4).
///
/// Mirrors `health_ai_tools.dart`. Bootstrap concatenates this list
/// into the cross-domain `deviceToolsProvider` only when the user has
/// opted into the Knowledge domain (`domainOptInsProvider`).
library;

import '../core/ai/runtime/device/tools/device_tool.dart';
import 'knowledge/ai_tools/list_due_reviews_tool.dart';
import 'knowledge/ai_tools/list_open_assumptions_tool.dart';
import 'knowledge/ai_tools/propose_concept_link_tool.dart';
import 'knowledge/ai_tools/recall_decision_tool.dart';
import 'knowledge/ai_tools/search_notes_tool.dart';
import 'knowledge/ai_tools/summarize_topic_evolution_tool.dart';

/// All KnowledgeOS device tools. Read-only except for
/// `propose_concept_link`, which returns a ProposalEnvelope and never
/// writes directly.
const List<DeviceTool> kKnowledgeDeviceTools = <DeviceTool>[
  RecallDecisionTool(),
  ListOpenAssumptionsTool(),
  ListDueReviewsTool(),
  SearchNotesTool(),
  ProposeConceptLinkTool(),
  SummarizeTopicEvolutionTool(),
];
