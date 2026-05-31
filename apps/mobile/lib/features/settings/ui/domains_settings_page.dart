import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/agents/agent.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth_providers;
import '../../../core/notifications/providers.dart' as notif_providers;
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../health/agents/providers.dart' as health_agent_providers;
import '../../health/data/health_sync_service.dart';
import '../../health/data/morning_briefing_preferences.dart';
import '../../health/data/providers.dart' as health_data;
import 'inline_setting_row.dart';

/// `/settings/domains` — the LifeOS domain console.
///
/// Pulled out of the Settings overview (2026-05-29) so the overview stops
/// growing/shrinking as domains toggle on, and so per-domain operations
/// (HealthOS sync / briefing) have a focused home instead of crowding the
/// global preferences list. The overview now links here with a single
/// row. FinanceOS is the always-on seed domain; HealthOS / KnowledgeOS are
/// per-user opt-ins (D-1.5) — enabling one activates its AI tools + Memory
/// indexing + IA shell entry.
class DomainsSettingsPage extends ConsumerWidget {
  const DomainsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optIns = ref.watch(auth_providers.domainOptInsProvider).value;
    final healthEnabled = optIns?.contains(DomainScope.health) ?? false;
    final knowledgeEnabled = optIns?.contains(DomainScope.knowledge) ?? false;
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.settingsDomainsTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s16,
          AppSpacing.s16,
          AppSpacing.s24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, AppSpacing.s12),
            child: Text(
              l10n.settingsDomainsIntro,
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                InlineLinkRow(
                  icon: FLucideIcons.wallet,
                  label: 'FinanceOS',
                  subtitle: l10n.settingsDomainsFinanceSubtitle,
                  trailingBadge: l10n.settingsDomainsEnabledBadge,
                  onTap: () {},
                ),
                _RowDivider(),
                InlineSwitchRow(
                  icon: FLucideIcons.heartPulse,
                  label: 'HealthOS',
                  subtitle: healthEnabled
                      ? l10n.settingsDomainsHealthEnabledSubtitle
                      : l10n.settingsDomainsHealthDisabledSubtitle,
                  value: healthEnabled,
                  onChanged: (v) {
                    ref
                        .read(auth_providers.domainOptInsProvider.notifier)
                        .setEnabled(DomainScope.health, v);
                  },
                ),
                if (healthEnabled) ...[
                  _RowDivider(),
                  InlineLinkRow(
                    icon: FLucideIcons.eye,
                    label: 'HealthOS · Today',
                    subtitle: l10n.settingsDomainsHealthTodaySubtitle,
                    onTap: () => context.goNamed(AppRouteNames.healthToday),
                  ),
                  _RowDivider(),
                  const _HealthPlatformSyncRow(),
                  _RowDivider(),
                  const _MorningBriefingRunRow(),
                  _RowDivider(),
                  const _MorningBriefingHourRow(),
                ],
                _RowDivider(),
                InlineSwitchRow(
                  icon: FLucideIcons.brain,
                  label: 'KnowledgeOS',
                  subtitle: knowledgeEnabled
                      ? l10n.settingsDomainsKnowledgeEnabledSubtitle
                      : l10n.settingsDomainsKnowledgeDisabledSubtitle,
                  value: knowledgeEnabled,
                  onChanged: (v) {
                    ref
                        .read(auth_providers.domainOptInsProvider.notifier)
                        .setEnabled(DomainScope.knowledge, v);
                  },
                ),
                if (knowledgeEnabled) ...[
                  _RowDivider(),
                  InlineLinkRow(
                    icon: FLucideIcons.inbox,
                    label: 'KnowledgeOS · Inbox',
                    subtitle: l10n.settingsDomainsKnowledgeInboxSubtitle,
                    onTap: () => context.goNamed(AppRouteNames.knowledgeInbox),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single-pixel ribbon divider between rows in a [SoftCard], matching the
/// settings-overview look (alpha 0.05, 14px horizontal inset).
class _RowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        height: 1,
        color: context.theme.colors.foreground.withValues(alpha: 0.05),
      ),
    );
  }
}

/// D-2.2 — manual "Sync from HealthKit / Health Connect" trigger.
///
/// Tapping requests permissions on first use, then pulls the last 30 days
/// into `health_metrics`. Background fetch / WorkManager scheduling lands
/// in D-2.5b; this is the dogfood path until then.
class _HealthPlatformSyncRow extends ConsumerStatefulWidget {
  const _HealthPlatformSyncRow();

  @override
  ConsumerState<_HealthPlatformSyncRow> createState() =>
      _HealthPlatformSyncRowState();
}

class _HealthPlatformSyncRowState
    extends ConsumerState<_HealthPlatformSyncRow> {
  bool _running = false;
  HealthSyncResult? _lastResult;

  Future<void> _run() async {
    if (_running) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _running = true);
    try {
      final service = await ref.read(
        health_data.healthSyncServiceProvider.future,
      );
      // Permissions are a precondition — request them if missing so the
      // user doesn't have to remember to do a separate "Connect" step.
      if (!await service.hasPermissions()) {
        final granted = await service.requestPermissions();
        if (!granted) {
          setState(() {
            _lastResult = HealthSyncResult.skipped(
              startedAt: DateTime.now().toUtc(),
              errorMessage: l10n.settingsDomainsHealthPermissionDenied,
            );
          });
          return;
        }
      }
      final result = await service.syncRange();
      setState(() => _lastResult = result);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _subtitle(AppLocalizations l10n) {
    final r = _lastResult;
    if (_running) return l10n.settingsDomainsHealthSyncRunning;
    if (r == null) return l10n.settingsDomainsHealthSyncIdle;
    if (!r.ok) return r.errorMessage ?? l10n.settingsDomainsHealthSyncFailed;
    return l10n.settingsDomainsHealthSyncSummary(
      r.upserted,
      r.unchanged,
      r.totalFetched,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InlineLinkRow(
      icon: FLucideIcons.refreshCcw,
      label: l10n.settingsDomainsHealthSyncTitle,
      subtitle: _subtitle(l10n),
      onTap: _running ? () {} : _run,
    );
  }
}

/// D-2.5b — manual "Run morning briefing now" trigger + notification
/// permission status.
///
/// The user usually doesn't need to tap this — the workmanager background
/// task fires the agent daily and posts a local notification. The button
/// exists for dogfood + first-run flows (permission grant, sanity check).
class _MorningBriefingRunRow extends ConsumerStatefulWidget {
  const _MorningBriefingRunRow();

  @override
  ConsumerState<_MorningBriefingRunRow> createState() =>
      _MorningBriefingRunRowState();
}

class _MorningBriefingRunRowState
    extends ConsumerState<_MorningBriefingRunRow> {
  bool _running = false;
  AgentRunResult? _lastResult;
  String? _errorMessage;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _errorMessage = null;
    });
    try {
      // First-time runs need notification permission so the toast ever
      // actually reaches the user; request it before kicking off the agent
      // so the prompt and the run are paired.
      final notifier = ref.read(notif_providers.notificationServiceProvider);
      if (await notifier.isAvailable() && !await notifier.hasPermissions()) {
        await notifier.requestPermissions();
      }
      // `refresh` re-runs the autoDispose provider even if it was already in
      // the cache from an earlier invocation. We await the future directly
      // so the result lands in our local state.
      final result = await ref.refresh(
        health_agent_providers.manualMorningBriefingRunProvider.future,
      );
      setState(() => _lastResult = result);
    } on Object catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _subtitle(AppLocalizations l10n) {
    if (_running) return l10n.settingsDomainsBriefingRunning;
    final err = _errorMessage;
    if (err != null) return l10n.settingsDomainsBriefingFailed(err);
    final r = _lastResult;
    if (r == null) {
      return l10n.settingsDomainsBriefingIdle;
    }
    return switch (r.status) {
      AgentRunStatus.completed => l10n.settingsDomainsBriefingCompleted(
        r.summary ?? l10n.settingsDomainsBriefingFallbackDone,
      ),
      AgentRunStatus.skipped => l10n.settingsDomainsBriefingSkipped(
        r.summary ?? l10n.settingsDomainsBriefingFallbackNoSignals,
      ),
      AgentRunStatus.failed => l10n.settingsDomainsBriefingRunFailed(
        r.error ?? l10n.settingsDomainsBriefingFallbackUnknown,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InlineLinkRow(
      icon: FLucideIcons.sunrise,
      label: l10n.settingsDomainsBriefingRunTitle,
      subtitle: _subtitle(l10n),
      onTap: _running ? () {} : _run,
    );
  }
}

/// D-2.5b follow-up — user-configurable preferred local hour for the daily
/// briefing. Defaults to 07:00. Background workmanager fires at OS
/// discretion (≈24h period) so the hour is honoured strictly only by
/// in-process scheduling; the value is still surfaced through the
/// `AgentSchedule` so the briefing's documented intent matches the user's
/// preference.
class _MorningBriefingHourRow extends ConsumerWidget {
  const _MorningBriefingHourRow();

  Future<void> _pick(BuildContext context, WidgetRef ref, int current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current, minute: 0),
      helpText: AppLocalizations.of(context).settingsDomainsBriefingTimeHelp,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    await ref.read(morningBriefingHourProvider.notifier).set(picked.hour);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hour = ref.watch(morningBriefingHourProvider);
    final label = hour.toString().padLeft(2, '0');
    final l10n = AppLocalizations.of(context);
    return InlineLinkRow(
      icon: FLucideIcons.clock,
      label: l10n.settingsDomainsBriefingTimeTitle,
      subtitle: l10n.settingsDomainsBriefingTimeSubtitle(label),
      trailingValue: '$label:00',
      onTap: () => _pick(context, ref, hour),
    );
  }
}
