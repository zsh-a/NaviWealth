/// HealthOS domain detail settings.
///
/// Shows HealthOS-specific operational controls: Today link, platform sync,
/// and source synchronization. Reached from the Settings overview's
/// HealthOS row.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
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
          if (!mounted) return;
          setState(() {
            _lastResult = HealthSyncResult.skipped(
              startedAt: DateTime.now().toUtc(),
              errorMessage: l10n.settingsDomainsHealthPermissionDenied,
            );
          });
          await service.recordResult(_lastResult!);
          ref.invalidate(health_data.healthSyncStatusProvider);
          ref.invalidate(health_data.healthPlatformStatusProvider);
          return;
        }
      }
      final result = await service.syncRange();
      if (!mounted) return;
      setState(() => _lastResult = result);
      ref.invalidate(health_data.healthSyncStatusProvider);
      ref.invalidate(health_data.healthPlatformStatusProvider);
      ref.invalidate(health_data.healthSourceDataSummaryProvider);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _subtitle(
    AppLocalizations l10n,
    HealthSyncStatus? persisted, {
    required health_data.HealthPlatformStatus? platformStatus,
    required health_data.HealthSourceDataSummary? sourceData,
  }) {
    final r = _lastResult;
    if (_running) return l10n.settingsDomainsHealthSyncRunning;
    if (platformStatus == null || platformStatus.checkFailed) {
      return l10n.healthSourceChecking;
    }
    if (!platformStatus.available) return l10n.healthSourceUnavailable;
    if (platformStatus.needsPermission) {
      return l10n.healthSourcePermissionRequired;
    }
    if (r == null) {
      if (persisted == null) return l10n.settingsDomainsHealthSyncIdle;
      if (!persisted.ok) {
        final code = persisted.errorCode?.toLowerCase() ?? '';
        if (code.contains('permission-denied')) {
          return l10n.settingsDomainsHealthPermissionDenied;
        }
        final details = <String>[l10n.healthSourceSyncFailed];
        details.add(
          l10n.healthSourceLastAttempt(
            _formatRelative(l10n, persisted.completedAt),
          ),
        );
        if (persisted.lastSuccessAt != null) {
          details.add(
            l10n.healthSourceLastSuccess(
              _formatRelative(l10n, persisted.lastSuccessAt!),
            ),
          );
        }
        return details.join(' · ');
      }
      return _metadata(
        l10n,
        sourceData?.platformLatestAt,
        l10n.healthSourceLastSync(_formatRelative(l10n, persisted.completedAt)),
      );
    }
    if (!r.ok) {
      final normalized = r.errorMessage?.toLowerCase() ?? '';
      return normalized.contains('permission') || normalized.contains('权限')
          ? l10n.settingsDomainsHealthPermissionDenied
          : l10n.settingsDomainsHealthSyncFailed;
    }
    return _metadata(
      l10n,
      sourceData?.platformLatestAt,
      l10n.settingsDomainsHealthSyncSummary(
        r.upserted,
        r.unchanged,
        r.totalFetched,
      ),
    );
  }

  String _metadata(AppLocalizations l10n, DateTime? dataAt, String syncText) {
    final parts = <String>[syncText];
    if (dataAt != null) {
      parts.add(l10n.healthSourceDataAt(_formatRelative(l10n, dataAt)));
    } else {
      parts.add(l10n.healthSourceNoData);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final persisted = ref.watch(health_data.healthSyncStatusProvider);
    final platformStatus = ref.watch(health_data.healthPlatformStatusProvider);
    final sourceData = ref.watch(health_data.healthSourceDataSummaryProvider);
    return InlineLinkRow(
      icon: FLucideIcons.refreshCw,
      label: l10n.settingsDomainsHealthSyncTitle,
      subtitle: _subtitle(
        l10n,
        persisted,
        platformStatus: platformStatus.value,
        sourceData: sourceData.value,
      ),
      trailingBadge: _badgeLabel(l10n, platformStatus, persisted),
      onTap: _running ? () {} : _run,
    );
  }

  String _badgeLabel(
    AppLocalizations l10n,
    AsyncValue<health_data.HealthPlatformStatus> status,
    HealthSyncStatus? persisted,
  ) {
    if (status.isLoading) return l10n.healthSourceChecking;
    final value = status.value;
    if (value == null || value.checkFailed || !value.available) {
      return l10n.healthSourceUnavailable;
    }
    if (value.needsPermission) return l10n.healthSourcePermissionRequired;
    if (_lastResult?.ok == false || persisted?.ok == false) {
      return l10n.healthSourceSyncFailed;
    }
    return l10n.healthSourceReady;
  }
}

String _formatRelative(AppLocalizations l10n, DateTime dt) =>
    AppFormatters.relativeTime(
      dt,
      justNow: l10n.aiChatRelativeJustNow,
      minutesAgo: l10n.aiChatRelativeMinutesAgo,
      hoursAgo: l10n.aiChatRelativeHoursAgo,
      daysAgo: l10n.aiChatRelativeDaysAgo,
      dateFallback: (d) {
        final mm = d.month.toString().padLeft(2, '0');
        final dd = d.day.toString().padLeft(2, '0');
        return '$mm-$dd';
      },
    );
