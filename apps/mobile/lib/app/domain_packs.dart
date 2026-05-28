/// Inventory of LifeOS domains (`docs/lifeos-shell.md` §4).
///
/// One entry per domain — adding a new LifeOS domain means landing
/// its tool barrel + shell spec + agents under `features/<domain>/`,
/// then appending one [DomainPack] entry here. `bootstrap.dart`
/// registers this list as [domainPackRegistryProvider]; the four
/// shell aggregators (device tools, prompt blocks, shell specs,
/// agent registry) derive from it automatically.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/agents/agent.dart';
import '../core/auth/domain_scope.dart';
import '../core/lifeos/domain_pack.dart';
import '../features/finance_ai_tools.dart';
import '../features/finance_domain_shell.dart';
import '../features/health/agents/morning_briefing_agent.dart';
import '../features/health/composition/health_domain_shell.dart';
import '../features/health_ai_tools.dart';
import '../features/knowledge/agents/providers.dart'
    as knowledge_agent_providers;
import '../features/knowledge/composition/knowledge_domain_shell.dart';
import '../features/knowledge_ai_tools.dart';

const DomainPack kFinancePack = DomainPack(
  scope: DomainScope.finance,
  deviceTools: kFinanceDeviceTools,
  systemPromptBlock: kFinanceSystemPromptBlock,
  shellSpecBuilder: financeDomainShell,
);

const DomainPack kHealthPack = DomainPack(
  scope: DomainScope.health,
  deviceTools: kHealthDeviceTools,
  systemPromptBlock: kHealthSystemPromptBlock,
  shellSpecBuilder: healthDomainShell,
  agentBuilder: _healthAgents,
);

const DomainPack kKnowledgePack = DomainPack(
  scope: DomainScope.knowledge,
  deviceTools: kKnowledgeDeviceTools,
  systemPromptBlock: kKnowledgeSystemPromptBlock,
  shellSpecBuilder: knowledgeDomainShell,
  agentBuilder: _knowledgeAgents,
);

/// Production inventory. `bootstrap.dart` overrides
/// [domainPackRegistryProvider] with this list. Tests can override
/// with a subset for reduced-matrix scenarios.
const List<DomainPack> kAllDomainPacks = <DomainPack>[
  kFinancePack,
  kHealthPack,
  kKnowledgePack,
];

List<Agent> _healthAgents(Ref ref) => <Agent>[
  ref.watch(morningBriefingAgentProvider),
];

List<Agent> _knowledgeAgents(Ref ref) =>
    ref.watch(knowledge_agent_providers.knowledgeAgentsProvider);
