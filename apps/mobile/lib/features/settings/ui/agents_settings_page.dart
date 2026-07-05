/// Cross-domain agent management settings.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_preference_store.dart';
import '../../../core/ai/agents/agent_presentation.dart';
import '../../../core/ai/agents/agent_registry.dart';
import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/current_user.dart';
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
        rows.add(
          _AgentSettingsRow(
            agent: agent,
            presentation: presentations[agent.id],
            preference: await preferenceStore.preferenceFor(
              ownerUserId: ownerUserId,
              agentId: agent.id,
            ),
            latestRun: await runStore.latestForAgent(
              ownerUserId: ownerUserId,
              agentId: agent.id,
            ),
          ),
        );
      }
      return rows;
    });

class AgentsSettingsPage extends ConsumerWidget {
  const AgentsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_agentSettingsRowsProvider);
    return AppPageScaffold(
      title: 'Agents',
      childPad: false,
      child: SettingsPageFrame(
        children: [
          const SettingsHintText(
            'Control scheduled LifeOS agents for active domains on this device.',
          ),
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
                return const AppEmptyState(
                  icon: FLucideIcons.bot,
                  title: 'No active agents',
                  message: 'Enable a LifeOS domain to see its agents here.',
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
  });

  final Agent agent;
  final AgentPresentationSpec? presentation;
  final AgentPreference preference;
  final AgentRunRecord? latestRun;
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
        result.error ?? result.summary ?? '${widget.row.agent.name} finished',
      );
      ref.invalidate(_agentSettingsRowsProvider);
    } finally {
      if (mounted) setState(() => _running = false);
    }
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
                FSwitch(value: enabled, onChange: _setEnabled)
              else
                const AppBadge(
                  label: 'Managed',
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
                label: _running ? 'Running' : 'Run now',
                onPress: _running || !enabled ? null : _runNow,
                busy: _running,
                prefix: const Icon(FLucideIcons.play, size: AppIconSizes.xs),
              ),
              AppBadge(
                label: enabled ? 'Enabled' : 'Disabled',
                size: AppBadgeSize.compact,
                tone: enabled ? AppBadgeTone.accent : AppBadgeTone.neutral,
              ),
              if (presentation?.notificationsSupported ?? false)
                const AppBadge(
                  label: 'Notifications',
                  size: AppBadgeSize.compact,
                  tone: AppBadgeTone.info,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(_AgentSettingsRow row, String? description) {
    final latest = row.latestRun;
    if (latest == null) return description ?? 'Never run';
    final status = switch (latest.status) {
      AgentRunLifecycleStatus.running => 'Running',
      AgentRunLifecycleStatus.ready => 'Ready',
      AgentRunLifecycleStatus.noFinding => 'No finding',
      AgentRunLifecycleStatus.failed => 'Failed',
    };
    final detail = latest.error ?? latest.summary;
    return detail == null ? status : '$status · $detail';
  }
}
