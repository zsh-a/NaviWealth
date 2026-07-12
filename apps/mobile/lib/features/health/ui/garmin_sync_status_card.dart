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
  const GarminSyncStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(health_data.garminSyncControllerProvider);

    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: switch (state) {
        GarminInitial() => _Disconnected(ref: ref),
        GarminRestoring() => const _Restoring(),
        GarminPendingMfa() => const _MfaPending(),
        GarminConnected(:final lastSyncAt, :final totalMetrics) => _Connected(
          ref: ref,
          lastSyncAt: lastSyncAt,
          totalMetrics: totalMetrics,
        ),
        GarminSyncing() => const _Syncing(),
        GarminError(:final issue) => _Error(ref: ref, issue: issue),
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
  final colors = context.theme.colors;
  return Row(
    children: [
      AppIconTile(
        icon: icon,
        color: colors.foreground,
        size: AppIconSizes.mlg,
        iconSize: AppIconSizes.xs,
        backgroundOpacity: AppOpacity.whisper,
        foregroundOpacity: AppOpacity.strong,
      ),
      const SizedBox(width: AppSpacing.s8),
      Expanded(
        child: Text(
          title,
          style: context.labelStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      badge,
    ],
  );
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

class _Disconnected extends StatelessWidget {
  const _Disconnected({required this.ref});
  final WidgetRef ref;

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
              label: l10n.healthGarminDisconnected,
              tone: AppBadgeTone.neutral,
              size: AppBadgeSize.compact,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => showGarminAccountBindSheet(context: context),
          child: Text(l10n.healthGarminConnect),
        ),
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
  const _MfaPending();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _buildHeader(
            context,
            icon: FLucideIcons.shield,
            title: l10n.healthGarminMfaRequired,
            badge: AppBadge(
              label: l10n.healthGarminVerifyBadge,
              tone: AppBadgeTone.warning,
              size: AppBadgeSize.compact,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => showGarminAccountBindSheet(context: context),
          child: Text(l10n.healthGarminEnterCode),
        ),
      ],
    );
  }
}

class _Connected extends StatelessWidget {
  const _Connected({
    required this.ref,
    required this.lastSyncAt,
    required this.totalMetrics,
  });
  final WidgetRef ref;
  final DateTime? lastSyncAt;
  final int totalMetrics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildHeader(
                context,
                icon: FLucideIcons.watch,
                title: l10n.healthGarminTitle,
                badge: AppBadge(
                  label: l10n.healthGarminConnected,
                  tone: AppBadgeTone.success,
                  size: AppBadgeSize.compact,
                ),
              ),
            ),
            if (lastSyncAt != null)
              Text(
                l10n.healthGarminLastSync(
                  '$totalMetrics',
                  _formatRelative(l10n, lastSyncAt!),
                ),
                style: context.captionStyle,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Expanded(
              child: FButton(
                variant: FButtonVariant.outline,
                onPress: () => ref
                    .read(health_data.garminSyncControllerProvider.notifier)
                    .syncNow(),
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
}

class _Syncing extends ConsumerWidget {
  const _Syncing();

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
        Row(
          children: [
            Expanded(
              child: _buildHeader(
                context,
                icon: FLucideIcons.watch,
                title: l10n.healthGarminTitle,
                badge: AppBadge(
                  label: l10n.healthGarminSyncingBadge,
                  tone: AppBadgeTone.info,
                  size: AppBadgeSize.compact,
                ),
              ),
            ),
            AppQuietButton(
              label: l10n.healthGarminCancelSync,
              onPress: () => ref
                  .read(health_data.garminSyncControllerProvider.notifier)
                  .cancelSync(),
            ),
          ],
        ),
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
  const _Error({required this.ref, required this.issue});
  final WidgetRef ref;
  final GarminSyncIssue issue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
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
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        AppQuietButton(
          label: issue.requiresReconnect
              ? l10n.healthGarminConnect
              : l10n.healthGarminRetry,
          onPress: () {
            if (issue.requiresReconnect) {
              showGarminAccountBindSheet(context: context);
              return;
            }
            ref
                .read(health_data.garminSyncControllerProvider.notifier)
                .syncNow();
          },
        ),
      ],
    );
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
