/// Inventory of LifeOS domains (`docs/lifeos-shell.md` §4).
///
/// One entry per domain — adding a new LifeOS domain means landing
/// its tool barrel + shell spec + routes + agents under
/// `features/<domain>/`, then appending one [DomainPack] entry here.
/// `bootstrap.dart` registers this list as
/// [domainPackRegistryProvider]; the shell aggregators (device tools,
/// prompt blocks, shell specs, agent registry, router branches,
/// primary tab paths, test preloaders) derive from it automatically.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/agents/agent.dart';
import '../core/auth/domain_scope.dart';
import '../core/lifeos/domain_pack.dart';
import '../features/finance/composition/finance_command_palette.dart';
import '../features/finance/composition/finance_routes.dart';
import '../features/finance_ai_tools.dart';
import '../features/finance_domain_shell.dart';
import '../features/health/agents/morning_briefing_agent.dart';
import '../features/health/composition/health_command_palette.dart';
import '../features/health/composition/health_domain_shell.dart';
import '../features/health/composition/health_routes.dart';
import '../features/health_ai_tools.dart';
import '../features/knowledge/agents/providers.dart'
    as knowledge_agent_providers;
import '../features/knowledge/composition/knowledge_command_palette.dart';
import '../features/knowledge/composition/knowledge_domain_shell.dart';
import '../features/knowledge/composition/knowledge_routes.dart';
import '../features/knowledge_ai_tools.dart';
import 'route_paths.dart';

const DomainPack kFinancePack = DomainPack(
  scope: DomainScope.finance,
  deviceTools: kFinanceDeviceTools,
  systemPromptBlock: kFinanceSystemPromptBlock,
  shellSpecBuilder: financeDomainShell,
  shellRouteBuilder: financeShellRoute,
  deferredPreloader: preloadFinanceDeferredRoutesForTest,
  tabPaths: [
    AppRoutes.home,
    AppRoutes.activity,
    AppRoutes.wealth,
    AppRoutes.plan,
  ],
  // `/cashflow*` is reachable from the Finance shell (cashflow page +
  // recurring + dividends) but isn't a primary tab — it's surfaced
  // through Wealth / Plan navigation. Listing it here keeps
  // `aiContextProvider` aware that those routes belong to Finance.
  additionalPathPrefixes: [AppRoutes.cashflow],
  commandPaletteEntriesBuilder: financeCommandPaletteEntries,
);

const DomainPack kHealthPack = DomainPack(
  scope: DomainScope.health,
  deviceTools: kHealthDeviceTools,
  systemPromptBlock: kHealthSystemPromptBlock,
  shellSpecBuilder: healthDomainShell,
  shellRouteBuilder: healthShellRoute,
  tabPaths: [
    AppRoutes.healthToday,
    AppRoutes.healthTrend,
    AppRoutes.healthPlan,
  ],
  agentBuilder: _healthAgents,
  commandPaletteEntriesBuilder: healthCommandPaletteEntries,
);

const DomainPack kKnowledgePack = DomainPack(
  scope: DomainScope.knowledge,
  deviceTools: kKnowledgeDeviceTools,
  systemPromptBlock: kKnowledgeSystemPromptBlock,
  shellSpecBuilder: knowledgeDomainShell,
  shellRouteBuilder: knowledgeShellRoute,
  tabPaths: [
    AppRoutes.knowledgeInbox,
    AppRoutes.knowledgeLibrary,
    AppRoutes.knowledgeReview,
  ],
  agentBuilder: _knowledgeAgents,
  commandPaletteEntriesBuilder: knowledgeCommandPaletteEntries,
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
