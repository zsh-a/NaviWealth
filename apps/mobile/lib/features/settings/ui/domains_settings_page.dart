import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth_providers;
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../health/data/health_sync_service.dart';
import '../../health/data/morning_briefing_preferences.dart';
import '../../health/data/providers.dart' as health_data;
import 'finance_domain_settings_section.dart';
import 'inline_setting_row.dart';

/// `/settings/domains` — LifeOS domain management.
///
/// FinanceOS is always on; optional domains expose enablement and
/// domain-specific controls here.
class DomainsSettingsPage extends ConsumerWidget {
  const DomainsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optIns = ref.watch(auth_providers.domainOptInsProvider).value;
    final healthEnabled = optIns?.contains(DomainScope.health) ?? false;
    final knowledgeEnabled = optIns?.contains(DomainScope.knowledge) ?? false;
    final l10n = AppLocalizations.of(context);

    return AppPageScaffold(
      title: l10n.settingsDomainsTitle,
      childPad: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s16,
          AppSpacing.s16,
          AppSpacing.s24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const FinanceDomainSettingsSection(),
          const SizedBox(height: AppSpacing.s16),
          // ── HealthOS ──
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: [
                InlineSwitchRow(
                  icon: FLucideIcons.heartPulse,
                  label: 'HealthOS',
                  subtitle: healthEnabled
                      ? l10n.settingsDomainsHealthEnabledSubtitle
                      : l10n.settingsDomainsHealthDisabledSubtitle,
                  value: healthEnabled,
                  onChanged: (v) =>
                      _setDomainEnabled(context, ref, DomainScope.health, v),
                ),
                if (healthEnabled) ...[
                  const AppDivider(),
                  InlineLinkRow(
                    icon: FLucideIcons.eye,
                    label: 'HealthOS · Today',
                    subtitle: l10n.settingsDomainsHealthTodaySubtitle,
                    onTap: () => context.goNamed(AppRouteNames.healthToday),
                  ),
                  const AppDivider(),
                  const _HealthPlatformSyncRow(),
                  const AppDivider(),
                  const _MorningBriefingHourRow(),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          // ── KnowledgeOS ──
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: [
                InlineSwitchRow(
                  icon: FLucideIcons.brain,
                  label: 'KnowledgeOS',
                  subtitle: knowledgeEnabled
                      ? l10n.settingsDomainsKnowledgeEnabledSubtitle
                      : l10n.settingsDomainsKnowledgeDisabledSubtitle,
                  value: knowledgeEnabled,
                  onChanged: (v) =>
                      _setDomainEnabled(context, ref, DomainScope.knowledge, v),
                ),
                if (knowledgeEnabled) ...[
                  const AppDivider(),
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

  Future<void> _setDomainEnabled(
    BuildContext context,
    WidgetRef ref,
    DomainScope scope,
    bool enabled,
  ) async {
    await ref
        .read(auth_providers.domainOptInsProvider.notifier)
        .setEnabled(scope, enabled);
    if (!context.mounted || enabled) return;
    final l10n = AppLocalizations.of(context);
    context.go(AppRoutes.settingsDomains);
    AppMessenger.show(
      context,
      ToastKind.info,
      l10n.settingsDomainsDisabledToast(_domainLabel(scope)),
    );
  }

  String _domainLabel(DomainScope scope) {
    return switch (scope) {
      DomainScope.finance => 'FinanceOS',
      DomainScope.health => 'HealthOS',
      DomainScope.knowledge => 'KnowledgeOS',
    };
  }
}

/// Manual "Sync from HealthKit / Health Connect" trigger.
///
/// Tapping requests permissions on first use, then pulls the last 30 days
/// into `health_metrics`.
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
      icon: FLucideIcons.refreshCw,
      label: l10n.settingsDomainsHealthSyncTitle,
      subtitle: _subtitle(l10n),
      onTap: _running ? () {} : _run,
    );
  }
}

/// User-configurable preferred local hour for the daily briefing.
/// Defaults to 07:00.
class _MorningBriefingHourRow extends ConsumerWidget {
  const _MorningBriefingHourRow();

  Future<void> _pick(BuildContext context, WidgetRef ref, int current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showAppSheet<int>(
      context: context,
      title: l10n.settingsDomainsBriefingTimeTitle,
      subtitle: l10n.settingsDomainsBriefingTimeHelp,
      footer: FButton(
        variant: FButtonVariant.outline,
        onPress: () => Navigator.of(context).maybePop(),
        child: Text(l10n.commonCancel),
      ),
      builder: (_) => _MorningBriefingHourSheet(selectedHour: current),
    );
    if (picked == null) return;
    await ref.read(morningBriefingHourProvider.notifier).set(picked);
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

class _MorningBriefingHourSheet extends StatelessWidget {
  const _MorningBriefingHourSheet({required this.selectedHour});

  final int selectedHour;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        for (var hour = 0; hour < 24; hour++)
          SizedBox(
            width: AppControlWidths.settingsShortLabel,
            child: FButton(
              variant: hour == selectedHour
                  ? FButtonVariant.primary
                  : FButtonVariant.outline,
              onPress: () => Navigator.of(context).pop(hour),
              child: Text('${hour.toString().padLeft(2, '0')}:00'),
            ),
          ),
      ],
    );
  }
}
