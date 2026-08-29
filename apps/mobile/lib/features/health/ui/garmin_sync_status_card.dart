/// Garmin sync status card for the Health Today page.
///
/// Compact card showing connection state and quick actions.
library;

import 'package:flutter/material.dart'
    show AlwaysStoppedAnimation, LinearProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/garmin/garmin_sync_controller.dart';
import '../data/garmin/garmin_sync_issue.dart';
import '../data/providers.dart' as health_data;
import 'garmin_account_bind_sheet.dart';

/// Garmin sync status card.
class GarminSyncStatusCard extends ConsumerWidget {
  const GarminSyncStatusCard({super.key, this.showActions = true});

  final bool showActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(health_data.garminSyncControllerProvider);
    final latestDataAt = ref
        .watch(health_data.healthSourceDataSummaryProvider)
        .value
        ?.garminLatestAt;

    return SoftCard(
      level: SoftCardLevel.raised,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: switch (state) {
        GarminInitial() => _Disconnected(
          latestDataAt: latestDataAt,
          showActions: showActions,
        ),
        GarminRestoring() => const _Restoring(),
        GarminPendingMfa() => _MfaPending(showActions: showActions),
        GarminConnected(
          :final lastSyncAt,
          :final totalMetrics,
          :final lastAttemptAt,
          :final lastErrorCode,
        ) =>
          _Connected(
            ref: ref,
            lastSyncAt: lastSyncAt,
            totalMetrics: totalMetrics,
            latestDataAt: latestDataAt,
            lastAttemptAt: lastAttemptAt,
            lastErrorCode: lastErrorCode,
            showActions: showActions,
          ),
        GarminSyncing() => _Syncing(showActions: showActions),
        GarminError(:final issue) => _Error(
          ref: ref,
          issue: issue,
          latestDataAt: latestDataAt,
          showActions: showActions,
        ),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared header
// ---------------------------------------------------------------------------

Widget _buildHeader(
  BuildContext context, {
  required IconData icon,
  required String title,
  required Widget badge,
}) {
  return AppMetricHeader(
    icon: icon,
    title: title,
    color: context.theme.colors.foreground,
    showChevron: false,
    trailing: Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpacing.s8),
      child: badge,
    ),
  );
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

class _Disconnected extends StatelessWidget {
  const _Disconnected({required this.latestDataAt, required this.showActions});
  final DateTime? latestDataAt;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.watch,
          title: l10n.healthGarminTitle,
          badge: AppBadge(
            label: l10n.healthGarminDisconnected,
            tone: AppBadgeTone.neutral,
            size: AppBadgeSize.compact,
          ),
        ),
        if (latestDataAt != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.healthSourceDataAt(_formatRelative(l10n, latestDataAt!)),
            style: context.captionStyle,
          ),
        ],
        if (showActions) ...[
          const SizedBox(height: AppSpacing.s8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FButton(
              variant: FButtonVariant.outline,
              onPress: () => showGarminAccountBindSheet(context: context),
              child: Text(l10n.healthGarminConnect),
            ),
          ),
        ],
      ],
    );
  }
}

class _Restoring extends StatelessWidget {
  const _Restoring();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _buildHeader(
            context,
            icon: FLucideIcons.watch,
            title: l10n.healthGarminTitle,
            badge: AppBadge(
              label: l10n.healthGarminRestoringBadge,
              tone: AppBadgeTone.info,
              size: AppBadgeSize.compact,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        const SizedBox(
          width: AppIconSizes.xs,
          height: AppIconSizes.xs,
          child: FProgress(),
        ),
      ],
    );
  }
}

class _MfaPending extends StatelessWidget {
  const _MfaPending({required this.showActions});

  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.shield,
          title: l10n.healthGarminMfaRequired,
          badge: AppBadge(
            label: l10n.healthGarminVerifyBadge,
            tone: AppBadgeTone.warning,
            size: AppBadgeSize.compact,
          ),
        ),
        if (showActions) ...[
          const SizedBox(height: AppSpacing.s8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FButton(
              variant: FButtonVariant.outline,
              onPress: () => showGarminAccountBindSheet(context: context),
              child: Text(l10n.healthGarminEnterCode),
            ),
          ),
        ],
      ],
    );
  }
}

class _Connected extends StatelessWidget {
  const _Connected({
    required this.ref,
    required this.lastSyncAt,
    required this.totalMetrics,
    required this.latestDataAt,
    required this.lastAttemptAt,
    required this.lastErrorCode,
    required this.showActions,
  });
  final WidgetRef ref;
  final DateTime? lastSyncAt;
  final int totalMetrics;
  final DateTime? latestDataAt;
  final DateTime? lastAttemptAt;
  final String? lastErrorCode;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.watch,
          title: l10n.healthGarminTitle,
          badge: AppBadge(
            label: lastErrorCode == null
                ? l10n.healthGarminConnected
                : l10n.healthGarminErrorBadge,
            tone: lastErrorCode == null
                ? AppBadgeTone.success
                : AppBadgeTone.error,
            size: AppBadgeSize.compact,
          ),
        ),
        if (lastSyncAt != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.healthGarminLastSync(
              '$totalMetrics',
              _formatRelative(l10n, lastSyncAt!),
            ),
            style: context.captionStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (lastErrorCode != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            _issueCodeMessage(l10n, lastErrorCode!),
            style: context.captionStyle.copyWith(
              color: context.appTheme.status.danger.fg,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (lastAttemptAt != null) ...[
            const SizedBox(height: AppSpacing.s2),
            Text(
              l10n.healthSourceLastAttempt(
                _formatRelative(l10n, lastAttemptAt!),
              ),
              style: context.microCaptionStyle,
            ),
          ],
        ],
        if (latestDataAt != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.healthSourceDataAt(_formatRelative(l10n, latestDataAt!)),
            style: context.captionStyle,
          ),
        ],
        const SizedBox(height: AppSpacing.s4),
        Row(
          children: [
            Icon(
              FLucideIcons.refreshCw,
              size: AppIconSizes.xs,
              color: context.theme.colors.foreground,
            ),
            const SizedBox(width: AppSpacing.s6),
            Expanded(
              child: Text(
                l10n.healthGarminAutoRenewEnabled,
                style: context.captionStyle,
              ),
            ),
          ],
        ),
        if (showActions) ...[
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => _syncGarmin(context),
                  child: Text(l10n.healthGarminSync),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppQuietButton(
                label: l10n.healthGarminDisconnect,
                onPress: () => _showDisconnectDialog(context, ref),
                tone: AppQuietButtonTone.danger,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _showDisconnectDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.healthGarminDisconnectTitle),
      body: Text(l10n.healthGarminDisconnectBody),
      cancelLabel: l10n.healthGarminCancel,
      confirmLabel: l10n.healthGarminDisconnect,
      destructive: true,
      icon: FLucideIcons.unlink,
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(health_data.garminSyncControllerProvider.notifier)
          .disconnect();
    }
  }

  Future<void> _syncGarmin(BuildContext context) async {
    await ref.read(health_data.garminSyncControllerProvider.notifier).syncNow();
    if (context.mounted) {
      ref.invalidate(health_data.healthSourceDataSummaryProvider);
    }
  }
}

class _Syncing extends ConsumerWidget {
  const _Syncing({required this.showActions});

  final bool showActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final state =
        ref.watch(health_data.garminSyncControllerProvider) as GarminSyncing;

    final hasProgress = state.totalDays > 0;
    final progress = hasProgress ? state.currentDay / state.totalDays : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.watch,
          title: l10n.healthGarminTitle,
          badge: AppBadge(
            label: l10n.healthGarminSyncingBadge,
            tone: AppBadgeTone.info,
            size: AppBadgeSize.compact,
          ),
        ),
        if (showActions) ...[
          const SizedBox(height: AppSpacing.s8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppQuietButton(
              label: l10n.healthGarminCancelSync,
              onPress: () => ref
                  .read(health_data.garminSyncControllerProvider.notifier)
                  .cancelSync(),
            ),
          ),
        ],
        if (hasProgress) ...[
          const SizedBox(height: AppSpacing.s6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: colors.muted.withValues(
                alpha: AppOpacity.highlight,
              ),
              valueColor: AlwaysStoppedAnimation(colors.primary),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            l10n.healthGarminSyncProgress(
              state.currentDay.toString(),
              state.totalDays.toString(),
              state.metricsCount.toString(),
            ),
            style: context.captionStyle,
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.s4),
          Row(
            children: [
              const SizedBox(
                width: AppIconSizes.xs,
                height: AppIconSizes.xs,
                child: FProgress(),
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(l10n.healthGarminSyncingData, style: context.captionStyle),
            ],
          ),
        ],
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({
    required this.ref,
    required this.issue,
    required this.latestDataAt,
    required this.showActions,
  });
  final WidgetRef ref;
  final GarminSyncIssue issue;
  final DateTime? latestDataAt;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.circleAlert,
          title: l10n.healthGarminSyncError,
          badge: AppBadge(
            label: l10n.healthGarminErrorBadge,
            tone: AppBadgeTone.error,
            size: AppBadgeSize.compact,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          _issueMessage(l10n, issue),
          style: context.captionStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (latestDataAt != null) ...[
          const SizedBox(height: AppSpacing.s2),
          Text(
            l10n.healthSourceDataAt(_formatRelative(l10n, latestDataAt!)),
            style: context.microCaptionStyle,
          ),
        ],
        if (showActions) ...[
          const SizedBox(height: AppSpacing.s8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppQuietButton(
              label: issue.requiresReconnect
                  ? l10n.healthGarminConnect
                  : l10n.healthGarminRetry,
              onPress: () {
                if (issue.requiresReconnect) {
                  showGarminAccountBindSheet(context: context);
                  return;
                }
                _retryGarmin(context);
              },
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _retryGarmin(BuildContext context) async {
    await ref.read(health_data.garminSyncControllerProvider.notifier).syncNow();
    if (context.mounted) {
      ref.invalidate(health_data.healthSourceDataSummaryProvider);
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Format a relative time label using the shared [AppFormatters.relativeTime].
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

String _issueMessage(AppLocalizations l10n, GarminSyncIssue issue) {
  switch (issue.code) {
    case 'auth_expired':
      return l10n.healthGarminErrorAuthExpired;
    case 'credentials_invalid':
      return l10n.healthGarminErrorCredentialsInvalid;
    case 'rate_limited':
      return l10n.healthGarminErrorRateLimited;
    case 'endpoint_unavailable':
      return l10n.healthGarminErrorEndpointUnavailable;
    case 'snapshot_missing':
    case 'snapshot_not_persisted':
    case 'persist_failed':
      return l10n.healthGarminErrorPersistFailed;
    case 'snapshot_unsupported':
      return l10n.healthGarminErrorUnsupportedSnapshot;
    default:
      return l10n.healthGarminErrorGeneric;
  }
}

String _issueCodeMessage(AppLocalizations l10n, String code) {
  return switch (code) {
    'auth_expired' => l10n.healthGarminErrorAuthExpired,
    'credentials_invalid' => l10n.healthGarminErrorCredentialsInvalid,
    'rate_limited' => l10n.healthGarminErrorRateLimited,
    'endpoint_unavailable' => l10n.healthGarminErrorEndpointUnavailable,
    'snapshot_missing' ||
    'snapshot_not_persisted' ||
    'persist_failed' => l10n.healthGarminErrorPersistFailed,
    'snapshot_unsupported' => l10n.healthGarminErrorUnsupportedSnapshot,
    _ => l10n.healthGarminErrorGeneric,
  };
}
