import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/ai/agents/agent.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../core/shell/settings_route_paths.dart';
import '../../features/health/agents/morning_briefing_agent.dart';
import '../../features/health/agents/providers.dart' as health_agent_providers;
import '../../features/health/agents/recovery_alert_agent.dart';
import '../../features/health/agents/weekly_summary_agent.dart';
import '../../features/health/composition/health_command_palette.dart';
import '../../features/health/composition/health_domain_shell.dart';
import '../../features/health/composition/health_routes.dart';
import '../../features/health/data/health_metric_memory_indexer.dart';
import '../../features/health/ui/health_domain_settings_page.dart';
import '../../features/health_ai_tools.dart';
import '../../l10n/gen/app_localizations.dart';
import '../agent_runtime/agent_runtime_health_overrides.dart';
import '../route_paths.dart';
import 'domain_settings_spec.dart';

final DomainPack kHealthPack = DomainPack(
  scope: DomainScope.health,
  deviceTools: kHealthDeviceTools,
  toolDescriptors: kHealthToolDescriptors,
  systemPromptBlock: kHealthSystemPromptBlock,
  shellSpecBuilder: healthDomainShell,
  shellRouteBuilder: healthShellRoute,
  deferredPreloader: preloadHealthDeferredRoutesForTest,
  tabPaths: [
    AppRoutes.healthToday,
    AppRoutes.healthTrend,
    AppRoutes.healthPlan,
  ],
  agentBuilder: _healthAgents,
  memoryBootstrapBuilder: _healthMemoryBootstrap,
  backgroundBootstrapBuilder: _healthBackgroundBootstrap,
  commandPaletteEntriesBuilder: healthCommandPaletteEntries,
  providerOverridesBuilder: agentRuntimeHealthProviderOverrides,
  settingsSpec: domainSettingsSpec(
    icon: FLucideIcons.heartPulse,
    label: 'HealthOS',
    subtitle: _healthSettingsSubtitle,
    routePath: SettingsRoutes.domainsHealth,
    routeName: SettingsRouteNames.domainsHealth,
    page: const HealthDomainSettingsPage(),
  ),
);

List<Agent> _healthAgents(Ref ref) => <Agent>[
  ref.watch(morningBriefingAgentProvider),
  ref.watch(recoveryAlertAgentProvider),
  ref.watch(weeklySummaryAgentProvider),
];

void _healthMemoryBootstrap(Ref ref) {
  ref.watch(healthMetricMemoryIndexerProvider);
}

void _healthBackgroundBootstrap(Ref ref) {
  ref.watch(health_agent_providers.morningBriefingCronProvider);
  ref.watch(health_agent_providers.garminSyncCronProvider);
  ref.watch(health_agent_providers.healthPlatformSyncCronProvider);
  unawaited(ref.read(health_agent_providers.pendingBriefingRunProvider.future));
  unawaited(
    ref.read(health_agent_providers.pendingGarminSyncRunProvider.future),
  );
  unawaited(
    ref.read(
      health_agent_providers.pendingHealthPlatformSyncRunProvider.future,
    ),
  );
}

String _healthSettingsSubtitle(AppLocalizations l10n, bool enabled) => enabled
    ? l10n.settingsDomainsHealthEnabledSubtitle
    : l10n.settingsDomainsHealthDisabledSubtitle;
