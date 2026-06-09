/// Garmin sync status card for the Health Today page.
///
/// Compact card showing connection state and quick actions.
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
        GarminRestoring() => const _Restoring(),
        GarminPendingMfa() => const _MfaPending(),
        GarminConnected(:final lastSyncAt, :final totalMetrics) =>
          _Connected(ref: ref, lastSyncAt: lastSyncAt, totalMetrics: totalMetrics),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.watch,
          title: 'Garmin Connect',
          badge: const AppBadge(
            label: 'Disconnected',
            tone: AppBadgeTone.neutral,
            size: AppBadgeSize.compact,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        SizedBox(
          width: double.infinity,
          child: FButton(
            onPress: () => showGarminAccountBindSheet(context: context),
            child: const Text('Connect'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.watch,
          title: 'Garmin Connect',
          badge: const AppBadge(
            label: 'Restoring',
            tone: AppBadgeTone.info,
            size: AppBadgeSize.compact,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: FProgress(),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              'Restoring session…',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.shield,
          title: 'MFA Required',
          badge: const AppBadge(
            label: 'Verify',
            tone: AppBadgeTone.warning,
            size: AppBadgeSize.compact,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        SizedBox(
          width: double.infinity,
          child: FButton(
            onPress: () => showGarminAccountBindSheet(context: context),
            child: const Text('Enter Code'),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.watch,
          title: 'Garmin Connect',
          badge: const AppBadge(
            label: 'Connected',
            tone: AppBadgeTone.success,
            size: AppBadgeSize.compact,
          ),
        ),
        if (lastSyncAt != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            'Last sync ${_formatRelative(lastSyncAt!)} · $totalMetrics metrics',
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
                child: const Text('Sync'),
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
      builder: (dialogCtx) => FDialog(
        title: const Text('Disconnect Garmin?'),
        body: const Text(
          'Synced data will remain in the app.',
        ),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FButton(
            onPress: () => Navigator.pop(dialogCtx, true),
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
  const _Syncing();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.watch,
          title: 'Garmin Connect',
          badge: const AppBadge(
            label: 'Syncing',
            tone: AppBadgeTone.info,
            size: AppBadgeSize.compact,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: FProgress(),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              'Syncing data…',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          icon: FLucideIcons.circleAlert,
          title: 'Sync Error',
          badge: const AppBadge(
            label: 'Error',
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
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Format a relative time label (e.g. "2h ago", "Yesterday").
String _formatRelative(DateTime dt) {
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  final local = dt.toLocal();
  return '${local.month}/${local.day}';
}
