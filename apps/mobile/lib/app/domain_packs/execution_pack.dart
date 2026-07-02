import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/ai/agents/agent.dart';
import '../../core/ai/composition/composite_proposal_applier.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../features/execution/agents/providers.dart'
    as execution_agent_providers;
import '../../features/execution/composition/execution_command_palette.dart';
import '../../features/execution/composition/execution_domain_shell.dart';
import '../../features/execution/composition/execution_proposal_applier.dart'
    as execution_proposals;
import '../../features/execution/composition/execution_proposal_kinds.dart'
    show kExecutionProposalKinds;
import '../../features/execution/composition/execution_routes.dart';
import '../../features/execution/data/execution_memory_indexer.dart';
import '../../features/execution_ai_tools.dart';
import '../../features/settings/ui/execution_domain_settings_page.dart';
import '../../l10n/gen/app_localizations.dart';
import '../agent_runtime/agent_runtime_execution_overrides.dart';
import '../route_paths.dart';
import 'domain_settings_spec.dart';

final DomainPack kExecutionPack = DomainPack(
  scope: DomainScope.execution,
  deviceTools: kExecutionDeviceTools,
  toolDescriptors: kExecutionToolDescriptors,
  proposalKinds: kExecutionProposalKinds,
  proposalApplierRouteBuilder: _executionProposalApplierRoute,
  systemPromptBlock: kExecutionSystemPromptBlock,
  shellSpecBuilder: executionDomainShell,
  shellRouteBuilder: executionShellRoute,
  tabPaths: [
    AppRoutes.executionToday,
    AppRoutes.executionCommitments,
    AppRoutes.executionReview,
  ],
  agentBuilder: _executionAgents,
  memoryBootstrapBuilder: _executionMemoryBootstrap,
  commandPaletteEntriesBuilder: executionCommandPaletteEntries,
  providerOverridesBuilder: agentRuntimeExecutionProviderOverrides,
  settingsSpec: domainSettingsSpec(
    icon: FLucideIcons.listTodo,
    label: 'ExecutionOS',
    subtitle: _executionSettingsSubtitle,
    routePath: AppRoutes.settingsDomainsExecution,
    routeName: AppRouteNames.domainsExecution,
    page: const ExecutionDomainSettingsPage(),
  ),
);

List<Agent> _executionAgents(Ref ref) =>
    ref.watch(execution_agent_providers.executionAgentsProvider);

void _executionMemoryBootstrap(Ref ref) {
  ref.watch(executionMemoryIndexerProvider);
}

String _executionSettingsSubtitle(AppLocalizations l10n, bool enabled) =>
    enabled
    ? l10n.settingsDomainsExecutionEnabledSubtitle
    : l10n.settingsDomainsExecutionDisabledSubtitle;

Future<ProposalApplierRoute> _executionProposalApplierRoute(Ref ref) async {
  final applier = await ref.watch(
    execution_proposals.executionProposalApplierProvider.future,
  );
  return ProposalApplierRoute(
    applier: applier,
    kinds: execution_proposals.kExecutionProposalAppliedKinds,
    tablePrefixes: const {execution_proposals.kExecutionTablePrefix},
  );
}
