/// Cross-domain agent management settings.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_preference_store.dart';
import '../../../core/ai/agents/agent_presentation.dart';
import '../../../core/ai/agents/agent_registry.dart';
import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/agents/ui/agent_result_card.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

final _agentSettingsRowsProvider =
    FutureProvider.autoDispose<List<_AgentSettingsRow>>((ref) async {
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final preferenceStore = await ref.watch(
        agent_providers.agentPreferenceStoreProvider.future,
      );
      final runStore = await ref.watch(
        agent_providers.agentRunStoreProvider.future,
      );
      final agents = ref.watch(agentRegistryProvider);
      final presentations = ref.watch(agentPresentationSpecsProvider);
      final rows = <_AgentSettingsRow>[];
      for (final agent in agents) {
        final latestRun = await runStore.latestForAgent(
          ownerUserId: ownerUserId,
          agentId: agent.id,
        );
        AgentArtifact? latestArtifact;
        if (latestRun?.artifactId != null) {
          final artifactStore = await ref.watch(
            agent_providers.agentArtifactStoreProvider.future,
          );
          latestArtifact = await artifactStore.read(latestRun!.artifactId!);
        }
        rows.add(
          _AgentSettingsRow(
            agent: agent,
            presentation: presentations[agent.id],
            preference: await preferenceStore.preferenceFor(
              ownerUserId: ownerUserId,
              agentId: agent.id,
            ),
            latestRun: latestRun,
            latestArtifact: latestArtifact,
          ),
        );
      }
      return rows;
    });

class AgentsSettingsPage extends ConsumerWidget {
  const AgentsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rows = ref.watch(_agentSettingsRowsProvider);
    return AppPageScaffold(
      title: l10n.agentSettingsTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          SettingsHintText(l10n.agentSettingsSubtitle),
          const SizedBox(height: AppSpacing.s12),
          rows.when(
            loading: () => const SkeletonCard(
              padding: EdgeInsets.all(AppSpacing.s16),
              child: SkeletonBox(width: double.infinity, height: 96),
            ),
            error: (error, _) => AppStatusBanner(
              kind: AppStatusKind.error,
              message: '$error',
              icon: FLucideIcons.triangleAlert,
            ),
            data: (items) {
              if (items.isEmpty) {
                return AppEmptyState(
                  icon: FLucideIcons.bot,
                  title: l10n.agentSettingsNoActiveTitle,
                  message: l10n.agentSettingsNoActiveMessage,
                  action: AppQuietButton(
                    label: l10n.agentSettingsManageDomains,
                    onPress: () => context.goNamed(SettingsRouteNames.domains),
                    prefix: const Icon(
                      FLucideIcons.settings2,
                      size: AppIconSizes.xs,
                    ),
                  ),
                );
              }
              final sections = _groupRowsByDomain(items);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AgentSettingsOverview(rows: items),
                  const SizedBox(height: AppSpacing.s12),
                  for (var i = 0; i < sections.length; i++) ...[
                    _AgentSettingsDomainSectionView(section: sections[i]),
                    if (i != sections.length - 1)
                      const SizedBox(height: AppSpacing.s12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AgentSettingsRow {
  const _AgentSettingsRow({
    required this.agent,
    required this.presentation,
    required this.preference,
    required this.latestRun,
    required this.latestArtifact,
  });

  final Agent agent;
  final AgentPresentationSpec? presentation;
  final AgentPreference preference;
  final AgentRunRecord? latestRun;
  final AgentArtifact? latestArtifact;
}

class _AgentSettingsDomainSection {
  const _AgentSettingsDomainSection({required this.domain, required this.rows});

  final DomainScope domain;
  final List<_AgentSettingsRow> rows;
}

List<_AgentSettingsDomainSection> _groupRowsByDomain(
  List<_AgentSettingsRow> rows,
) {
  final grouped = <DomainScope, List<_AgentSettingsRow>>{};
  for (final row in rows) {
    final domain = row.presentation?.domain ?? DomainScope.finance;
    grouped.putIfAbsent(domain, () => <_AgentSettingsRow>[]).add(row);
  }
  return [
    for (final domain in DomainScope.values)
      if (grouped[domain]?.isNotEmpty ?? false)
        _AgentSettingsDomainSection(domain: domain, rows: grouped[domain]!),
  ];
}

class _AgentSettingsOverview extends StatelessWidget {
  const _AgentSettingsOverview({required this.rows});

  final List<_AgentSettingsRow> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = rows.where((row) => row.preference.enabled).length;
    final attention = rows
        .where(
          (row) =>
              row.latestRun?.status == AgentRunLifecycleStatus.ready ||
              row.latestRun?.status == AgentRunLifecycleStatus.failed,
        )
        .length;
    final notificationCapable = rows
        .where((row) => row.presentation?.notificationsSupported ?? false)
        .length;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Row(
        children: [
          AppIconTile(
            icon: FLucideIcons.bot,
            color: context.theme.colors.primary,
            size: AppSpacing.s40,
            iconSize: AppIconSizes.md,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.agentSettingsTitle, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  '$enabled/${rows.length} ${l10n.agentSettingsEnabled.toLowerCase()} · '
                  '$attention ${l10n.agentRunStatusReady.toLowerCase()} · '
                  '$notificationCapable ${l10n.agentSettingsNotifications.toLowerCase()}',
                  style: context.captionStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentSettingsDomainSectionView extends StatelessWidget {
  const _AgentSettingsDomainSectionView({required this.section});

  final _AgentSettingsDomainSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: Text(
            _domainLabel(section.domain),
            style: context.captionLabelStyle.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
          child: Column(
            children: [
              for (var i = 0; i < section.rows.length; i++) ...[
                _AgentSettingsRowTile(row: section.rows[i]),
                if (i != section.rows.length - 1) const AppGradientDivider(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AgentSettingsRowTile extends ConsumerStatefulWidget {
  const _AgentSettingsRowTile({required this.row});

  final _AgentSettingsRow row;

  @override
  ConsumerState<_AgentSettingsRowTile> createState() =>
      _AgentSettingsRowTileState();
}

class _AgentSettingsRowTileState extends ConsumerState<_AgentSettingsRowTile> {
  bool _running = false;

  Future<void> _setEnabled(bool enabled) async {
    final ownerUserId = await ref.read(currentUserIdProvider)();
    final store = await ref.read(
      agent_providers.agentPreferenceStoreProvider.future,
    );
    await store.setEnabled(
      ownerUserId: ownerUserId,
      agentId: widget.row.agent.id,
      enabled: enabled,
      updatedAt: DateTime.now().toUtc(),
    );
    final revision = ref.read(
      agent_providers.agentPreferenceRevisionProvider.notifier,
    );
    revision.state = revision.state + 1;
    ref.invalidate(_agentSettingsRowsProvider);
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    final ownerUserId = await ref.read(currentUserIdProvider)();
    final store = await ref.read(
      agent_providers.agentPreferenceStoreProvider.future,
    );
    await store.setNotificationsEnabled(
      ownerUserId: ownerUserId,
      agentId: widget.row.agent.id,
      enabled: enabled,
      updatedAt: DateTime.now().toUtc(),
    );
    final revision = ref.read(
      agent_providers.agentPreferenceRevisionProvider.notifier,
    );
    revision.state = revision.state + 1;
    ref.invalidate(_agentSettingsRowsProvider);
  }

  Future<void> _runNow() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final controller = await ref.read(agentRunControllerProvider.future);
      final result = await controller.runOnceById(widget.row.agent.id);
      if (!mounted) return;
      AppMessenger.show(
        context,
        result.status == AgentRunStatus.failed
            ? ToastKind.error
            : ToastKind.success,
        result.error ??
            result.summary ??
            AppLocalizations.of(
              context,
            ).agentSettingsRunFinished(widget.row.agent.name),
      );
      ref.invalidate(_agentSettingsRowsProvider);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _showHistory() async {
    final ownerUserId = await ref.read(currentUserIdProvider)();
    final store = await ref.read(agent_providers.agentRunStoreProvider.future);
    final runs = await store.listForAgent(
      ownerUserId: ownerUserId,
      agentId: widget.row.agent.id,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    await showAppSheet<void>(
      context: context,
      title: l10n.agentSettingsHistoryTitle(widget.row.agent.name),
      maxHeightFactor: 0.88,
      builder: (sheetContext) => _AgentRunHistoryList(runs: runs),
    );
  }

  Future<void> _showDetails() async {
    final row = widget.row;
    final l10n = AppLocalizations.of(context);
    final label = row.presentation?.label(l10n) ?? row.agent.name;
    await showAppSheet<void>(
      context: context,
      title: label,
      subtitle: _domainLabel(row.presentation?.domain ?? DomainScope.finance),
      maxHeightFactor: 0.88,
      builder: (_) => _AgentSettingsDetailSheet(
        row: row,
        running: _running,
        onRunNow: _runNow,
        onShowHistory: _showHistory,
        onSetEnabled: _setEnabled,
        onSetNotificationsEnabled: _setNotificationsEnabled,
        onRowsChanged: () => ref.invalidate(_agentSettingsRowsProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final row = widget.row;
    final presentation = row.presentation;
    final enabled = row.preference.enabled;
    final label = presentation?.label(l10n) ?? row.agent.name;
    final description = presentation?.description(l10n);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        children: [
          Expanded(
            child: FTappable(
              onPress: _showDetails,
              child: Row(
                children: [
                  AppIconTile(
                    icon: presentation?.icon ?? FLucideIcons.bot,
                    color: enabled ? colors.primary : colors.mutedForeground,
                    size: AppSpacing.s32,
                    iconSize: AppIconSizes.sm,
                    backgroundOpacity: AppOpacity.subtle,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: context.theme.typography.body.sm,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s6),
                            _AgentRunStatusDot(row: row),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          _compactSubtitle(context, row, description),
                          style: context.captionStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Icon(
                    FLucideIcons.chevronRight,
                    size: AppIconSizes.xs,
                    color: colors.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s10),
          if (presentation?.userToggleable ?? true)
            FSwitch(
              key: ValueKey<String>('agent-enabled-${row.agent.id}'),
              value: enabled,
              onChange: _setEnabled,
            )
          else
            AppBadge(
              label: l10n.agentSettingsManagedBadge,
              size: AppBadgeSize.compact,
              tone: AppBadgeTone.neutral,
            ),
        ],
      ),
    );
  }
}

class _AgentSettingsDetailSheet extends ConsumerStatefulWidget {
  const _AgentSettingsDetailSheet({
    required this.row,
    required this.running,
    required this.onRunNow,
    required this.onShowHistory,
    required this.onSetEnabled,
    required this.onSetNotificationsEnabled,
    required this.onRowsChanged,
  });

  final _AgentSettingsRow row;
  final bool running;
  final Future<void> Function() onRunNow;
  final Future<void> Function() onShowHistory;
  final Future<void> Function(bool) onSetEnabled;
  final Future<void> Function(bool) onSetNotificationsEnabled;
  final VoidCallback onRowsChanged;

  @override
  ConsumerState<_AgentSettingsDetailSheet> createState() =>
      _AgentSettingsDetailSheetState();
}

class _AgentSettingsDetailSheetState
    extends ConsumerState<_AgentSettingsDetailSheet> {
  late bool _enabled;
  late bool _notificationsEnabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.row.preference.enabled;
    _notificationsEnabled = widget.row.preference.notificationsEnabled;
  }

  void _setEnabled(bool value) {
    setState(() => _enabled = value);
    unawaited(widget.onSetEnabled(value));
  }

  void _setNotificationsEnabled(bool value) {
    setState(() => _notificationsEnabled = value);
    unawaited(widget.onSetNotificationsEnabled(value));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final row = widget.row;
    final presentation = row.presentation;
    final enabled = _enabled;
    final description = presentation?.description(l10n);
    final formatters = context.formatters(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconTile(
              icon: presentation?.icon ?? FLucideIcons.bot,
              color: enabled ? colors.primary : colors.mutedForeground,
              size: AppSpacing.s40,
              iconSize: AppIconSizes.md,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _detailSubtitle(context, row, description),
                    style: context.theme.typography.body.sm,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Wrap(
                    spacing: AppSpacing.s8,
                    runSpacing: AppSpacing.s8,
                    children: [
                      AppBadge(
                        label: enabled
                            ? l10n.agentSettingsEnabled
                            : l10n.agentSettingsDisabled,
                        size: AppBadgeSize.compact,
                        tone: enabled
                            ? AppBadgeTone.accent
                            : AppBadgeTone.neutral,
                      ),
                      AppBadge(
                        label: _scheduleLabel(l10n, row.agent.schedule),
                        size: AppBadgeSize.compact,
                        tone: AppBadgeTone.neutral,
                      ),
                      if (row.latestRun != null)
                        AppBadge(
                          label: l10n.agentSettingsLastRunAt(
                            formatters.dateTime(
                              row.latestRun!.startedAt.toLocal(),
                            ),
                          ),
                          size: AppBadgeSize.compact,
                          tone: AppBadgeTone.neutral,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          child: Column(
            children: [
              _AgentDetailActionRow(
                icon: FLucideIcons.power,
                title: l10n.agentSettingsEnabled,
                subtitle: enabled
                    ? l10n.agentSettingsEnabled
                    : l10n.agentSettingsDisabled,
                trailing: presentation?.userToggleable ?? true
                    ? FSwitch(value: enabled, onChange: _setEnabled)
                    : AppBadge(
                        label: l10n.agentSettingsManagedBadge,
                        size: AppBadgeSize.compact,
                        tone: AppBadgeTone.neutral,
                      ),
              ),
              if (presentation?.notificationsSupported ?? false) ...[
                const AppGradientDivider(),
                _AgentDetailActionRow(
                  icon: FLucideIcons.bell,
                  title: l10n.agentSettingsNotifications,
                  subtitle: _notificationsEnabled
                      ? l10n.agentSettingsEnabled
                      : l10n.agentSettingsDisabled,
                  trailing: FSwitch(
                    key: ValueKey<String>(
                      'agent-notifications-${row.agent.id}',
                    ),
                    value: _notificationsEnabled,
                    onChange: enabled ? _setNotificationsEnabled : null,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            AppQuietButton(
              label: widget.running
                  ? l10n.agentSettingsRunning
                  : l10n.agentSettingsRunNow,
              onPress: widget.running || !enabled ? null : widget.onRunNow,
              busy: widget.running,
              prefix: const Icon(FLucideIcons.play, size: AppIconSizes.xs),
            ),
            if (row.latestArtifact != null)
              AppQuietButton(
                label: l10n.agentSettingsViewResult,
                onPress: () => showAgentArtifactSheet(
                  context: context,
                  artifact: row.latestArtifact!,
                  onVisibilityChanged: widget.onRowsChanged,
                ),
                prefix: const Icon(
                  FLucideIcons.externalLink,
                  size: AppIconSizes.xs,
                ),
              ),
            if (row.latestRun != null)
              AppQuietButton(
                label: l10n.agentSettingsViewHistory,
                onPress: widget.onShowHistory,
                prefix: const Icon(FLucideIcons.history, size: AppIconSizes.xs),
              ),
          ],
        ),
      ],
    );
  }
}

class _AgentDetailActionRow extends StatelessWidget {
  const _AgentDetailActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s10,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: AppIconSizes.h18,
            color: context.theme.colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.captionLabelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  subtitle,
                  style: context.captionStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s10),
          trailing,
        ],
      ),
    );
  }
}

class _AgentRunStatusDot extends StatelessWidget {
  const _AgentRunStatusDot({required this.row});

  final _AgentSettingsRow row;

  @override
  Widget build(BuildContext context) {
    final latest = row.latestRun;
    final l10n = AppLocalizations.of(context);
    if (!row.preference.enabled) {
      return AppBadge(
        label: l10n.agentSettingsDisabled,
        size: AppBadgeSize.compact,
        tone: AppBadgeTone.neutral,
      );
    }
    if (latest == null) return const SizedBox.shrink();
    return AppBadge(
      label: _statusLabel(l10n, latest.status),
      size: AppBadgeSize.compact,
      tone: switch (latest.status) {
        AgentRunLifecycleStatus.failed => AppBadgeTone.error,
        AgentRunLifecycleStatus.ready => AppBadgeTone.accent,
        _ => AppBadgeTone.neutral,
      },
    );
  }
}

class _AgentRunHistoryList extends ConsumerWidget {
  const _AgentRunHistoryList({required this.runs});

  final List<AgentRunRecord> runs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    if (runs.isEmpty) {
      return AppEmptyState(
        icon: FLucideIcons.history,
        title: l10n.agentSettingsHistoryEmptyTitle,
        message: l10n.agentSettingsHistoryEmptyMessage,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < runs.length; i++) ...[
          AgentRunStatusCard(
            record: runs[i],
            metaLabel: _historyMetaLabel(l10n, formatters, runs[i]),
          ),
          if (i != runs.length - 1) const SizedBox(height: AppSpacing.s12),
        ],
      ],
    );
  }
}

String _historyMetaLabel(
  AppLocalizations l10n,
  AppFormatters formatters,
  AgentRunRecord run,
) {
  return '${_triggerLabel(l10n, run.trigger)} · '
      '${formatters.dateTime(run.startedAt.toLocal())}';
}

String _triggerLabel(AppLocalizations l10n, AgentRunTrigger trigger) {
  return switch (trigger) {
    AgentRunTrigger.manual => l10n.agentSettingsTriggerManual,
    AgentRunTrigger.schedule => l10n.agentSettingsTriggerSchedule,
    AgentRunTrigger.backgroundDue => l10n.agentSettingsTriggerBackgroundDue,
    AgentRunTrigger.catchUp => l10n.agentSettingsTriggerCatchUp,
  };
}

String _compactSubtitle(
  BuildContext context,
  _AgentSettingsRow row,
  String? description,
) {
  final l10n = AppLocalizations.of(context);
  if (!row.preference.enabled) return l10n.agentSettingsDisabled;
  final latest = row.latestRun;
  if (latest == null) {
    final fallback = description ?? l10n.agentSettingsNeverRun;
    return '${_scheduleLabel(l10n, row.agent.schedule)} · $fallback';
  }
  return '${_statusLabel(l10n, latest.status)} · '
      '${_relativeTimeShort(latest.startedAt)} · '
      '${_scheduleLabel(l10n, row.agent.schedule)}';
}

String _detailSubtitle(
  BuildContext context,
  _AgentSettingsRow row,
  String? description,
) {
  final latest = row.latestRun;
  final l10n = AppLocalizations.of(context);
  if (latest == null) return description ?? l10n.agentSettingsNeverRun;
  final status = _statusLabel(l10n, latest.status);
  final detail = latest.error ?? latest.summary;
  return detail == null
      ? status
      : l10n.agentSettingsStatusWithDetail(status, detail);
}

String _statusLabel(AppLocalizations l10n, AgentRunLifecycleStatus status) {
  return switch (status) {
    AgentRunLifecycleStatus.running => l10n.agentRunStatusRunning,
    AgentRunLifecycleStatus.ready => l10n.agentRunStatusReady,
    AgentRunLifecycleStatus.noFinding => l10n.agentRunStatusNoFinding,
    AgentRunLifecycleStatus.failed => l10n.agentRunStatusFailed,
  };
}

String _relativeTimeShort(DateTime at) {
  final delta = DateTime.now().toUtc().difference(at.toUtc());
  if (delta.inMinutes < 1) return '0m';
  if (delta.inHours < 1) return '${delta.inMinutes}m';
  if (delta.inDays < 1) return '${delta.inHours}h';
  return '${delta.inDays}d';
}

String _domainLabel(DomainScope domain) {
  return switch (domain) {
    DomainScope.finance => 'FinanceOS',
    DomainScope.health => 'HealthOS',
    DomainScope.knowledge => 'KnowledgeOS',
    DomainScope.execution => 'ExecutionOS',
  };
}

String _scheduleLabel(AppLocalizations l10n, AgentSchedule schedule) {
  final cadence = _intervalLabel(l10n, schedule.interval);
  final hour = schedule.preferredHourLocal;
  if (hour == null) return cadence;
  final time = '${hour.toString().padLeft(2, '0')}:00';
  return '$cadence · ${l10n.agentSettingsAroundTime(time)}';
}

String _intervalLabel(AppLocalizations l10n, Duration interval) {
  if (interval.inDays > 0 && interval.inHours == interval.inDays * 24) {
    final days = interval.inDays;
    if (days == 365) return l10n.agentSettingsCadenceYearly;
    if (days % 365 == 0) return l10n.recurringEveryYear(days ~/ 365);
    if (days == 30) return l10n.agentSettingsCadenceMonthly;
    if (days % 30 == 0) return l10n.recurringEveryMonth(days ~/ 30);
    if (days == 7) return l10n.agentSettingsCadenceWeekly;
    if (days % 7 == 0) return l10n.recurringEveryWeek(days ~/ 7);
    if (days == 1) return l10n.agentSettingsCadenceDaily;
    return l10n.recurringEveryDay(days);
  }
  final hours = interval.inHours <= 0 ? 1 : interval.inHours;
  return l10n.agentSettingsEveryHours(hours);
}
