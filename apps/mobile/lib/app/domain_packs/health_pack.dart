import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/agents/agent_presentation.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/shell/settings_route_paths.dart';
import 'package:naviwealth/features/health/agents/morning_briefing_agent.dart';
import 'package:naviwealth/features/health/agents/providers.dart'
    as health_agent_providers;
import 'package:naviwealth/features/health/agents/recovery_alert_agent.dart';
import 'package:naviwealth/features/health/agents/weekly_summary_agent.dart';
import 'package:naviwealth/features/health/composition/health_command_palette.dart';
import 'package:naviwealth/features/health/composition/health_domain_shell.dart';
import 'package:naviwealth/features/health/composition/health_routes.dart';
import 'package:naviwealth/features/health/data/health_metric_memory_indexer.dart';
import 'package:naviwealth/features/health/data_management/health_data_management.dart';
import 'package:naviwealth/features/health/health_ai_tools.dart';
import 'package:naviwealth/features/health/ui/health_domain_settings_page.dart';
import 'package:naviwealth/features/health/ui/settings/health_notification_settings.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../agent_runtime/overrides/agent_runtime_health_overrides.dart';
import '../routing/route_paths.dart';
import 'domain_settings_spec.dart';
import 'health_life_contribution.dart';

final DomainPack kHealthPack = DomainPack(
  scope: DomainScope.health,
  deviceTools: kHealthDeviceTools,
  toolDescriptors: kHealthToolDescriptors,
  intentDescriptors: kHealthAgentIntentDescriptors,
  systemPromptBlock: kHealthSystemPromptBlock,
  shellSpecBuilder: healthDomainShell,
  shellRouteBuilder: healthShellRoute,
  deferredPreloader: preloadHealthDeferredRoutesForTest,
  tabPaths: [AppRoutes.healthToday, AppRoutes.healthTrend],
  agentBuilder: _healthAgents,
  agentPresentationSpecs: const [
    AgentPresentationSpec(
      agentId: kMorningBriefingAgentId,
      domain: DomainScope.health,
      icon: FLucideIcons.sun,
      label: _morningBriefingLabel,
      description: _morningBriefingDescription,
      notificationsSupported: true,
      placement: AgentResultPlacement.domainHome,
    ),
    AgentPresentationSpec(
      agentId: kRecoveryAlertAgentId,
      domain: DomainScope.health,
      icon: FLucideIcons.heartPulse,
      label: _recoveryAlertLabel,
      description: _recoveryAlertDescription,
      notificationsSupported: true,
      placement: AgentResultPlacement.domainHome,
    ),
    AgentPresentationSpec(
      agentId: kWeeklySummaryAgentId,
      domain: DomainScope.health,
      icon: FLucideIcons.clipboardCheck,
      label: _weeklySummaryLabel,
      description: _weeklySummaryDescription,
      placement: AgentResultPlacement.domainReview,
    ),
  ],
  memorySourcePrefixes: const [
    'health:',
    kMorningBriefingMemorySource,
    kRecoveryAlertMemorySource,
    kWeeklySummaryMemorySource,
  ],
  memoryBootstrapBuilder: _healthMemoryBootstrap,
  backgroundBootstrapBuilder: _healthBackgroundBootstrap,
  commandPaletteEntriesBuilder: healthCommandPaletteEntries,
  providerOverridesBuilder: agentRuntimeHealthProviderOverrides,
  lifeSignalBuilder: healthLifeSignals,
  sourceRouteResolver: healthSourceRoute,
  notificationSettingsBuilder: healthNotificationSettings,
  dataManagementSpec: healthDataManagementSpec,
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

String _morningBriefingLabel(AppLocalizations l10n) =>
    l10n.agentPresentationMorningBriefingLabel;

String _morningBriefingDescription(AppLocalizations l10n) =>
    l10n.agentPresentationMorningBriefingDescription;

String _recoveryAlertLabel(AppLocalizations l10n) =>
    l10n.agentPresentationRecoveryAlertLabel;

String _recoveryAlertDescription(AppLocalizations l10n) =>
    l10n.agentPresentationRecoveryAlertDescription;

String _weeklySummaryLabel(AppLocalizations l10n) =>
    l10n.agentPresentationWeeklySummaryLabel;

String _weeklySummaryDescription(AppLocalizations l10n) =>
    l10n.agentPresentationWeeklySummaryDescription;
