/// HealthOS domain detail settings.
///
/// Shows HealthOS-specific operational controls: Today link, platform sync,
/// and source synchronization. Reached from the Settings overview's
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
import '../data/health_sync_status.dart';
import '../data/providers.dart' as health_data;
import 'garmin_sync_status_card.dart';

class HealthDomainSettingsPage extends ConsumerWidget {
  const HealthDomainSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: 'HealthOS',
      childPad: false,
      child: SettingsPageFrame(
        children: <Widget>[
          Text(l10n.healthSettingsSourcesTitle, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(l10n.healthSettingsSourcesHelp, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s8),
          const SoftCard.raised(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(children: <Widget>[_HealthPlatformSyncRow()]),
          ),
          const GarminSyncStatusCard(),
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
          await service.recordResult(_lastResult!);
          ref.invalidate(health_data.healthSyncStatusProvider);
          return;
        }
      }
      final result = await service.syncRange();
      setState(() => _lastResult = result);
      ref.invalidate(health_data.healthSyncStatusProvider);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _subtitle(AppLocalizations l10n, HealthSyncStatus? persisted) {
    final r = _lastResult;
    if (_running) return l10n.settingsDomainsHealthSyncRunning;
    if (r == null) {
      if (persisted == null) return l10n.settingsDomainsHealthSyncIdle;
      if (!persisted.ok) {
        return persisted.errorCode ?? l10n.settingsDomainsHealthSyncFailed;
      }
      return l10n.settingsDomainsHealthSyncSummary(
        persisted.upserted,
        persisted.unchanged,
        persisted.totalFetched,
      );
    }
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
    final persisted = ref.watch(health_data.healthSyncStatusProvider);
    return InlineLinkRow(
      icon: FLucideIcons.refreshCw,
      label: l10n.settingsDomainsHealthSyncTitle,
      subtitle: _subtitle(l10n, persisted),
      onTap: _running ? () {} : _run,
    );
  }
}
