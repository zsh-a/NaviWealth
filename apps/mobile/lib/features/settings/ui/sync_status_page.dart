import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import '../../../core/logging/providers.dart';
import '../../../core/sync/providers.dart';
import '../../../core/sync/sync_status.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Diagnostic page showing the current sync engine state in one place:
/// hero status indicator, outbox depth, last cursor, and last error.
/// Reachable from Settings → Sync.
class SyncStatusPage extends ConsumerWidget {
  const SyncStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final eventAsync = ref.watch(syncStatusEventStreamProvider);

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.syncStatusTitle),
        actions: [
          IconButton(
            tooltip: l10n.syncStatusRefreshNow,
            icon: const Icon(Icons.refresh),
            onPressed: () => _triggerSyncNow(ref),
          ),
        ],
      ),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.s24),
            child: Text(l10n.syncStatusBusError(e.toString())),
          ),
        ),
        data: (event) => _SyncStatusBody(event: event),
      ),
    );
  }

  Future<void> _triggerSyncNow(WidgetRef ref) async {
    final scheduler = await ref.read(syncSchedulerProvider.future);
    await scheduler?.triggerNow();
    ref.invalidate(syncCursorProvider);
    ref.invalidate(syncOutboxDepthProvider);
  }
}

class _SyncStatusBody extends ConsumerWidget {
  const _SyncStatusBody({required this.event});

  final SyncStatusEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final outboxAsync = ref.watch(syncOutboxDepthProvider);
    final cursorAsync = ref.watch(syncCursorProvider);
    final session = ref.watch(authSessionProvider);
    final config = ref.watch(appConfigProvider);

    return ListView(
      padding: Spacing.pageMobile.copyWith(
        bottom:
            Spacing.pageMobile.bottom +
            Spacing.floatingBarClearance +
            MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _HeroStatusCard(event: event),
        const SizedBox(height: Spacing.s16),
        GlassSectionHeader(title: l10n.syncStatusPendingHeader),
        _OutboxCard(
          depth: outboxAsync.value,
          isLoading: outboxAsync.isLoading,
          onSyncNow: session == null
              ? null
              : () async {
                  final scheduler = await ref.read(
                    syncSchedulerProvider.future,
                  );
                  await scheduler?.triggerNow();
                  ref.invalidate(syncCursorProvider);
                  ref.invalidate(syncOutboxDepthProvider);
                },
        ),
        if (event.lastError != null) ...[
          GlassSectionHeader(title: l10n.syncStatusErrorHeader),
          _ErrorCard(message: event.lastError!),
        ],
        GlassSectionHeader(title: l10n.syncStatusDetailsHeader),
        _DetailsCard(
          event: event,
          cursor: cursorAsync.value?.toString(),
          deviceId: session?.deviceId,
          apiBaseUrl: kDebugMode ? config.apiBaseUrl : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero status card
// ---------------------------------------------------------------------------

class _HeroStatusCard extends StatelessWidget {
  const _HeroStatusCard({required this.event});

  final SyncStatusEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = _palette(context, event.status);

    return LiquidGlassCard(
      layer: GlassLayer.tertiary,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s20,
        vertical: Spacing.s24,
      ),
      child: Row(
        children: [
          _StatusOrb(palette: palette, status: event.status),
          const SizedBox(width: Spacing.s20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusHeadline(l10n, event.status),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Spacing.s4),
                Text(
                  _statusSubtitle(l10n, event),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusHeadline(AppLocalizations l10n, SyncStatus s) => switch (s) {
    SyncStatus.idle => l10n.syncStatusHeadlineIdle,
    SyncStatus.syncing => l10n.syncStatusHeadlineSyncing,
    SyncStatus.online => l10n.syncStatusHeadlineOnline,
    SyncStatus.offline => l10n.syncStatusHeadlineOffline,
    SyncStatus.failed => l10n.syncStatusHeadlineFailed,
  };

  String _statusSubtitle(AppLocalizations l10n, SyncStatusEvent e) {
    final last = e.lastSuccessAt;
    if (last == null) return l10n.syncStatusSubtitleNeverSynced;
    return l10n.syncStatusSubtitleLastSynced(_relativeTime(l10n, last));
  }
}

class _StatusOrb extends StatefulWidget {
  const _StatusOrb({required this.palette, required this.status});

  final _StatusPalette palette;
  final SyncStatus status;

  @override
  State<_StatusOrb> createState() => _StatusOrbState();
}

class _StatusOrbState extends State<_StatusOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant _StatusOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.status == SyncStatus.syncing) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final pulse = widget.status == SyncStatus.syncing
            ? 1 + 0.18 * _ctrl.value
            : 1.0;
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.palette.container,
          ),
          alignment: Alignment.center,
          child: Transform.scale(
            scale: pulse,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.palette.foreground,
              ),
              alignment: Alignment.center,
              child: Icon(
                _statusIcon(widget.status),
                size: 16,
                color: widget.palette.onForeground,
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _statusIcon(SyncStatus s) => switch (s) {
    SyncStatus.idle => Icons.cloud_outlined,
    SyncStatus.syncing => Icons.sync,
    SyncStatus.online => Icons.cloud_done_outlined,
    SyncStatus.offline => Icons.cloud_off_outlined,
    SyncStatus.failed => Icons.error_outline,
  };
}

// ---------------------------------------------------------------------------
// Outbox card
// ---------------------------------------------------------------------------

class _OutboxCard extends StatelessWidget {
  const _OutboxCard({
    required this.depth,
    required this.isLoading,
    required this.onSyncNow,
  });

  final int? depth;
  final bool isLoading;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pending = depth ?? 0;
    final hasPending = pending > 0;

    return LiquidGlassCard(
      layer: GlassLayer.tertiary,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s16,
        vertical: Spacing.s12,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasPending
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
            ),
            alignment: Alignment.center,
            child: Icon(
              hasPending ? Icons.outbox_outlined : Icons.check,
              color: hasPending ? scheme.primary : scheme.onSurfaceVariant,
              size: 20,
            ),
          ),
          const SizedBox(width: Spacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoading
                      ? l10n.syncStatusPendingLoading
                      : (hasPending
                            ? l10n.syncStatusPendingCount(pending)
                            : l10n.syncStatusPendingNone),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Spacing.s2),
                Text(
                  hasPending
                      ? l10n.syncStatusPendingCaption
                      : l10n.syncStatusPendingCaptionEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onSyncNow != null)
            AppButton.tertiary(
              label: l10n.syncStatusActionSyncNow,
              onPressed: onSyncNow,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error card
// ---------------------------------------------------------------------------

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = SemanticColors.of(context);

    return LiquidGlassCard(
      layer: GlassLayer.tertiary,
      padding: const EdgeInsets.all(Spacing.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: semantic.danger,
            size: 22,
          ),
          const SizedBox(width: Spacing.s12),
          Expanded(
            child: SelectableText(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: semantic.onDangerContainer,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Details card (state code, cursor, device, optional API URL)
// ---------------------------------------------------------------------------

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.event,
    required this.cursor,
    required this.deviceId,
    required this.apiBaseUrl,
  });

  final SyncStatusEvent event;
  final String? cursor;
  final String? deviceId;
  final String? apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return LiquidGlassCard(
      layer: GlassLayer.tertiary,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _DetailRow(
            label: l10n.syncStatusDetailState,
            value: event.status.name,
          ),
          const Divider(height: 1),
          _DetailRow(
            label: l10n.syncStatusDetailUpdatedAt,
            value: _formatLocal(event.at),
          ),
          if (deviceId != null) ...[
            const Divider(height: 1),
            _DetailRow(
              label: l10n.syncStatusDetailDevice,
              value: _shortDeviceId(deviceId!),
              monospace: true,
            ),
          ],
          const Divider(height: 1),
          _DetailRow(
            label: l10n.syncStatusDetailCursor,
            value: cursor ?? l10n.syncStatusDetailCursorUnset,
            monospace: true,
            wrap: true,
          ),
          if (apiBaseUrl != null) ...[
            const Divider(height: 1),
            _DetailRow(
              label: l10n.syncStatusDetailEndpoint,
              value: apiBaseUrl!,
              monospace: true,
              wrap: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.wrap = false,
  });

  final String label;
  final String value;
  final bool monospace;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valueStyle = (monospace ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
        ?.copyWith(
          color: scheme.onSurface,
          fontFeatures: monospace
              ? const [FontFeature.tabularFigures()]
              : null,
          fontFamily: monospace ? 'monospace' : null,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s16,
        vertical: Spacing.s12,
      ),
      child: Row(
        crossAxisAlignment: wrap
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: valueStyle,
              maxLines: wrap ? null : 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _StatusPalette {
  const _StatusPalette({
    required this.foreground,
    required this.onForeground,
    required this.container,
  });

  final Color foreground;
  final Color onForeground;
  final Color container;
}

_StatusPalette _palette(BuildContext context, SyncStatus s) {
  final scheme = Theme.of(context).colorScheme;
  final semantic = SemanticColors.of(context);
  return switch (s) {
    SyncStatus.idle => _StatusPalette(
      foreground: scheme.onSurfaceVariant,
      onForeground: scheme.surface,
      container: scheme.surfaceContainerHighest,
    ),
    SyncStatus.syncing => _StatusPalette(
      foreground: scheme.primary,
      onForeground: scheme.onPrimary,
      container: scheme.primaryContainer,
    ),
    SyncStatus.online => _StatusPalette(
      foreground: semantic.success,
      onForeground: semantic.onSuccess,
      container: semantic.successContainer,
    ),
    SyncStatus.offline => _StatusPalette(
      foreground: semantic.warning,
      onForeground: semantic.onWarning,
      container: semantic.warningContainer,
    ),
    SyncStatus.failed => _StatusPalette(
      foreground: semantic.danger,
      onForeground: semantic.onDanger,
      container: semantic.dangerContainer,
    ),
  };
}

String _shortDeviceId(String id) {
  if (id.length <= 12) return id;
  return '${id.substring(0, 8)}…${id.substring(id.length - 4)}';
}

String _formatLocal(DateTime ts) {
  final local = ts.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _relativeTime(AppLocalizations l10n, DateTime ts) {
  final diff = DateTime.now().difference(ts);
  if (diff.inSeconds < 45) return l10n.syncStatusJustNow;
  if (diff.inMinutes < 60) return l10n.syncStatusMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.syncStatusHoursAgo(diff.inHours);
  return l10n.syncStatusDaysAgo(diff.inDays);
}
