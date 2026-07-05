/// Cross-domain agent management settings.
library;

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
              return SoftCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      _AgentSettingsRowTile(row: items[i]),
                      if (i != items.length - 1) const AppGradientDivider(),
                    ],
                  ],
                ),
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

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final row = widget.row;
    final presentation = row.presentation;
    final enabled = row.preference.enabled;
    final label = presentation?.label(l10n) ?? row.agent.name;
    final description = presentation?.description(l10n);
    final formatters = context.formatters(ref);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: presentation?.icon ?? FLucideIcons.bot,
                color: enabled ? colors.primary : colors.mutedForeground,
                size: AppSpacing.s32,
                iconSize: AppIconSizes.sm,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: context.theme.typography.body.sm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      _subtitle(row, description),
                      style: context.captionStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
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
          const SizedBox(height: AppSpacing.s10),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              AppQuietButton(
                label: _running
                    ? l10n.agentSettingsRunning
                    : l10n.agentSettingsRunNow,
                onPress: _running || !enabled ? null : _runNow,
                busy: _running,
                prefix: const Icon(FLucideIcons.play, size: AppIconSizes.xs),
              ),
              if (row.latestArtifact != null)
                AppQuietButton(
                  label: l10n.agentSettingsViewResult,
                  onPress: () => showAgentArtifactSheet(
                    context: context,
                    artifact: row.latestArtifact!,
                    onVisibilityChanged: () =>
                        ref.invalidate(_agentSettingsRowsProvider),
                  ),
                  prefix: const Icon(
                    FLucideIcons.externalLink,
                    size: AppIconSizes.xs,
                  ),
                ),
              if (row.latestRun != null)
                AppQuietButton(
                  label: l10n.agentSettingsViewHistory,
                  onPress: _showHistory,
                  prefix: const Icon(
                    FLucideIcons.history,
                    size: AppIconSizes.xs,
                  ),
                ),
              AppBadge(
                label: enabled
                    ? l10n.agentSettingsEnabled
                    : l10n.agentSettingsDisabled,
                size: AppBadgeSize.compact,
                tone: enabled ? AppBadgeTone.accent : AppBadgeTone.neutral,
              ),
              AppBadge(
                label: _scheduleLabel(l10n, row.agent.schedule),
                size: AppBadgeSize.compact,
                tone: AppBadgeTone.neutral,
              ),
              if (row.latestRun != null)
                AppBadge(
                  label: l10n.agentSettingsLastRunAt(
                    formatters.dateTime(row.latestRun!.startedAt.toLocal()),
                  ),
                  size: AppBadgeSize.compact,
                  tone: AppBadgeTone.neutral,
                ),
              if (presentation?.notificationsSupported ?? false)
                _AgentNotificationToggle(
                  agentId: row.agent.id,
                  label: l10n.agentSettingsNotifications,
                  value: row.preference.notificationsEnabled,
                  enabled: enabled,
                  onChange: _setNotificationsEnabled,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(_AgentSettingsRow row, String? description) {
    final latest = row.latestRun;
    final l10n = AppLocalizations.of(context);
    if (latest == null) return description ?? l10n.agentSettingsNeverRun;
    final status = switch (latest.status) {
      AgentRunLifecycleStatus.running => l10n.agentRunStatusRunning,
      AgentRunLifecycleStatus.ready => l10n.agentRunStatusReady,
      AgentRunLifecycleStatus.noFinding => l10n.agentRunStatusNoFinding,
      AgentRunLifecycleStatus.failed => l10n.agentRunStatusFailed,
    };
    final detail = latest.error ?? latest.summary;
    return detail == null
        ? status
        : l10n.agentSettingsStatusWithDetail(status, detail);
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

class _AgentNotificationToggle extends StatelessWidget {
  const _AgentNotificationToggle({
    required this.agentId,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChange,
  });

  final String agentId;
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.muted.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: context.captionStyle),
            const SizedBox(width: AppSpacing.s8),
            FSwitch(
              key: ValueKey<String>('agent-notifications-$agentId'),
              value: value,
              onChange: enabled ? onChange : null,
            ),
          ],
        ),
      ),
    );
  }
}
