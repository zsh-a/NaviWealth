/// HealthOS domain detail settings.
///
/// Shows HealthOS-specific operational controls: Today link, platform sync,
/// and morning briefing time. Reached from the Settings overview's
/// HealthOS row.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/health_sync_service.dart';
import '../data/morning_briefing_preferences.dart';
import '../data/providers.dart' as health_data;

class HealthDomainSettingsPage extends ConsumerWidget {
  const HealthDomainSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AppPageScaffold(
      title: 'HealthOS',
      childPad: false,
      child: SettingsPageFrame(
        children: <Widget>[
          SoftCard(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: <Widget>[
                _HealthPlatformSyncRow(),
                AppGradientDivider(),
                _BriefingHourRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Platform sync ────────────────────────────────────────────────────────────

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

// ── Briefing hour ────────────────────────────────────────────────────────────

class _BriefingHourRow extends ConsumerWidget {
  const _BriefingHourRow();

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
      builder: (_) => _BriefingHourSheet(selectedHour: current),
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

/// Compact horizontal-scrollable hour picker.
class _BriefingHourSheet extends StatelessWidget {
  const _BriefingHourSheet({required this.selectedHour});

  final int selectedHour;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SizedBox(
      height: AppControlHeights.pickerStrip,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
        itemCount: 24,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s6),
        itemBuilder: (_, index) {
          final selected = index == selectedHour;
          return GestureDetector(
            onTap: () => Navigator.of(context).pop(index),
            child: AnimatedContainer(
              duration: AppMotionPolicy.duration(context, Motion.medium),
              curve: Motion.standardDecelerate,
              width: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? colors.primary.withValues(alpha: AppOpacity.subtle)
                    : colors.muted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: selected
                      ? colors.primary.withValues(alpha: AppOpacity.prominent)
                      : colors.border.withValues(alpha: AppOpacity.muted),
                ),
              ),
              child: Text(
                '${index.toString().padLeft(2, '0')}:00',
                style: selected
                    ? context.captionLabelStyle.copyWith(color: colors.primary)
                    : context.captionStyle.copyWith(color: colors.foreground),
              ),
            ),
          );
        },
      ),
    );
  }
}
