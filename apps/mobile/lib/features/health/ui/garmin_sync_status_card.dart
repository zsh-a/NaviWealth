/// Garmin sync status card for the Health Today page.
///
/// Shows connection state, last sync time, and a "Sync now" button.
library;

import 'package:flutter/material.dart' show showAdaptiveDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
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
        GarminPendingMfa() => const _MfaPending(),
        GarminConnected(:final lastSyncAt, :final totalMetrics) =>
          _Connected(
            ref: ref,
            lastSyncAt: lastSyncAt,
            totalMetrics: totalMetrics,
          ),
        GarminSyncing(:final startedAt) => _Syncing(startedAt: startedAt),
        GarminError(:final message) => _Error(ref: ref, message: message),
      },
    );
  }
}

class _Disconnected extends StatelessWidget {
  const _Disconnected({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(FLucideIcons.watch, size: 20, color: colors.foreground),
            const SizedBox(width: AppSpacing.s8),
            Text(
              'Garmin Connect',
              style: typography.md.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s4,
              ),
              decoration: BoxDecoration(
                color: colors.muted,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                'Not connected',
                style: typography.xs.copyWith(color: colors.mutedForeground),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        Text(
          'Connect your Garmin account to sync health data.',
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
        const SizedBox(height: AppSpacing.s12),
        FButton(
          onPress: () => showGarminAccountBindSheet(context: context),
          child: const Text('Connect Garmin'),
        ),
      ],
    );
  }
}

class _MfaPending extends StatelessWidget {
  const _MfaPending();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(FLucideIcons.shield, size: 20, color: colors.foreground),
            const SizedBox(width: AppSpacing.s8),
            Text(
              'MFA Required',
              style: typography.md.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          'Please complete MFA verification.',
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
        const SizedBox(height: AppSpacing.s12),
        FButton(
          onPress: () => showGarminAccountBindSheet(context: context),
          child: const Text('Enter MFA Code'),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(FLucideIcons.watch, size: 20, color: colors.foreground),
            const SizedBox(width: AppSpacing.s8),
            Text(
              'Garmin Connect',
              style: typography.md.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s4,
              ),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                'Connected',
                style: typography.xs.copyWith(color: colors.primary),
              ),
            ),
          ],
        ),
        if (lastSyncAt != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Last sync: ${_formatTime(lastSyncAt!)} · $totalMetrics metrics',
            style: typography.sm.copyWith(color: colors.mutedForeground),
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
                child: const Text('Sync now'),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            FButton(
              variant: FButtonVariant.outline,
              onPress: () => _showDisconnectDialog(context, ref),
              child: const Text('Disconnect'),
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
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => FDialog(
        title: const Text('Disconnect Garmin?'),
        body: const Text(
          'This will remove your Garmin credentials. '
          'Synced data will remain in the app.',
        ),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FButton(
            onPress: () => Navigator.pop(dialogContext, true),
            child: const Text('Disconnect'),
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
  const _Syncing({required this.startedAt});
  final DateTime startedAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: FProgress(),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              'Syncing...',
              style: typography.md.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          'Started ${_formatTime(startedAt)}',
          style: typography.sm.copyWith(color: colors.mutedForeground),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(FLucideIcons.circleAlert,
                size: 20, color: colors.destructive),
            const SizedBox(width: AppSpacing.s8),
            Text(
              'Sync Error',
              style: typography.md.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.destructive,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          message,
          style: typography.sm.copyWith(color: colors.mutedForeground),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.s12),
        FButton(
          onPress: () => ref
              .read(health_data.garminSyncControllerProvider.notifier)
              .syncNow(),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}
