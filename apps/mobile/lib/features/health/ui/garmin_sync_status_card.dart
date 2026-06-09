/// Garmin sync status card for the Health Today page.
///
/// Compact card showing connection state and quick actions.
library;

import 'package:flutter/material.dart' show showAdaptiveDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/garmin/garmin_sync_controller.dart';
import '../data/providers.dart' as health_data;
import 'garmin_account_bind_sheet.dart';

/// Garmin sync status card.
class GarminSyncStatusCard extends ConsumerWidget {
  const GarminSyncStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(health_data.garminSyncControllerProvider);

    return FCard(
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
        GarminError(:final message) => _Error(ref: ref, message: message),
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
  final typography = context.theme.typography;
  return Row(
    children: [
      Icon(icon, size: 18, color: colors.foreground),
      const SizedBox(width: AppSpacing.s8),
      Text(title, style: typography.sm.copyWith(fontWeight: FontWeight.w600)),
      const Spacer(),
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
        const SizedBox(height: AppSpacing.s12),
        SizedBox(
          width: double.infinity,
          child: FButton(
            onPress: () => showGarminAccountBindSheet(context: context),
            child: Text(l10n.healthGarminConnect),
          ),
        ),
      ],
    );
  }
}

class _Restoring extends StatelessWidget {
  const _Restoring();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.watch,
          title: l10n.healthGarminTitle,
          badge: AppBadge(
            label: l10n.healthGarminRestoringBadge,
            tone: AppBadgeTone.info,
            size: AppBadgeSize.compact,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            const SizedBox(width: 14, height: 14, child: FProgress()),
            const SizedBox(width: AppSpacing.s8),
            Text(
              l10n.healthGarminRestoringSession,
              style: typography.xs.copyWith(color: colors.mutedForeground),
            ),
          ],
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
        const SizedBox(height: AppSpacing.s12),
        SizedBox(
          width: double.infinity,
          child: FButton(
            onPress: () => showGarminAccountBindSheet(context: context),
            child: Text(l10n.healthGarminEnterCode),
          ),
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
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.watch,
          title: l10n.healthGarminTitle,
          badge: AppBadge(
            label: l10n.healthGarminConnected,
            tone: AppBadgeTone.success,
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
            style: typography.xs.copyWith(color: colors.mutedForeground),
          ),
        ],
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            Expanded(
              child: FButton(
                onPress: () => ref
                    .read(health_data.garminSyncControllerProvider.notifier)
                    .syncNow(),
                child: Text(l10n.healthGarminSync),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            FButton(
              variant: FButtonVariant.outline,
              onPress: () => _showDisconnectDialog(context, ref),
              child: Text(l10n.healthGarminDisconnect),
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
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogCtx) => FDialog(
        title: Text(l10n.healthGarminDisconnectTitle),
        body: Text(l10n.healthGarminDisconnectBody),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.healthGarminCancel),
          ),
          FButton(
            onPress: () => Navigator.pop(dialogCtx, true),
            child: Text(l10n.healthGarminDisconnect),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(health_data.garminSyncControllerProvider.notifier)
          .disconnect();
    }
  }
}

class _Syncing extends StatelessWidget {
  const _Syncing();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
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
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            const SizedBox(width: 14, height: 14, child: FProgress()),
            const SizedBox(width: AppSpacing.s8),
            Text(
              l10n.healthGarminSyncingData,
              style: typography.xs.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.ref, required this.message});
  final WidgetRef ref;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
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
        const SizedBox(height: AppSpacing.s4),
        Text(
          message,
          style: typography.xs.copyWith(color: colors.mutedForeground),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => ref
              .read(health_data.garminSyncControllerProvider.notifier)
              .syncNow(),
          child: Text(l10n.healthGarminRetry),
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
