import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/auth/providers.dart';
import '../../../core/config/providers.dart';
import '../../../core/sync/providers.dart';
import '../../../core/sync/sync_status.dart';
import '../../../design_system/design_system.dart';
import '../../../features/finance/data/diagnostics/local_table_counts.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Diagnostic page surfacing the current sync engine state at a glance:
/// hero status, three quick-read stat tiles, and a collapsible details
/// panel. Reachable from Settings → Sync.
class SyncStatusPage extends ConsumerWidget {
  const SyncStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final eventAsync = ref.watch(syncStatusEventStreamProvider);
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.syncStatusTitle),
        prefixes: [backHeaderAction(context)],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.refreshCw),
            onPress: () => _triggerSyncNow(ref),
          ),
        ],
      ),
      childPad: false,
      child: eventAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s24),
            child: Text(l10n.syncStatusBusError(e.toString())),
          ),
        ),
        data: (event) => _Body(event: event),
      ),
    );
  }
}

Future<void> _triggerSyncNow(WidgetRef ref) async {
  final scheduler = await ref.read(syncSchedulerProvider.future);
  await scheduler?.triggerNow();
  ref.invalidate(syncCursorProvider);
  ref.invalidate(syncOutboxDepthProvider);
  ref.invalidate(financeLocalTableCountsProvider);
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _Body extends ConsumerWidget {
  const _Body({required this.event});

  final SyncStatusEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outboxAsync = ref.watch(syncOutboxDepthProvider);
    final cursorAsync = ref.watch(syncCursorProvider);
    final countsAsync = ref.watch(financeLocalTableCountsProvider);
    final session = ref.watch(authSessionProvider);
    final config = ref.watch(appConfigProvider);

    final localTotal = countsAsync.value?.values.fold<int>(0, (a, b) => a + b);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16).copyWith(
        bottom:
            const EdgeInsets.all(AppSpacing.s16).bottom +
            64 +
            MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _HeroCard(
          event: event,
          onSyncNow: session == null ? null : () => _triggerSyncNow(ref),
        ),
        const SizedBox(height: AppSpacing.s12),
        _StatGrid(
          pending: outboxAsync.value,
          localTotal: localTotal,
          lastSyncAt: event.lastSuccessAt,
        ),
        if (event.lastError != null) ...[
          const SizedBox(height: AppSpacing.s12),
          _ErrorCard(message: event.lastError!),
        ],
        if (event.conflicts.hasFindings) ...[
          const SizedBox(height: AppSpacing.s12),
          _ConflictCard(diagnostics: event.conflicts),
        ],
        const SizedBox(height: AppSpacing.s12),
        _DiagnosticsCard(
          event: event,
          cursor: cursorAsync.value,
          deviceId: session?.deviceId,
          apiBaseUrl: kDebugMode ? config.apiBaseUrl : null,
        ),
        if (kDebugMode) ...[
          const SizedBox(height: AppSpacing.s12),
          _LocalCountsCard(counts: countsAsync.value),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero card — animated status orb + headline + inline Sync action
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.event, required this.onSyncNow});

  final SyncStatusEvent event;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = _palette(context, event.status);
    final syncing = event.status == SyncStatus.syncing;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s20, AppSpacing.s20, AppSpacing.s12, AppSpacing.s20),
      child: Row(
        children: [
          _StatusOrb(palette: palette, status: event.status),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusHeadline(l10n, event.status),
                  style: context.theme.typography.lg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  _heroSubtitle(l10n, event),
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          if (onSyncNow != null && !syncing) ...[
            const SizedBox(width: 8),
            FButton(
              variant: FButtonVariant.ghost,
              onPress: onSyncNow,
              child: Text(l10n.syncStatusActionSyncNow),
            ),
          ],
        ],
      ),
    );
  }
}

String _statusHeadline(AppLocalizations l10n, SyncStatus s) => switch (s) {
  SyncStatus.idle => l10n.syncStatusHeadlineIdle,
  SyncStatus.syncing => l10n.syncStatusHeadlineSyncing,
  SyncStatus.online => l10n.syncStatusHeadlineOnline,
  SyncStatus.offline => l10n.syncStatusHeadlineOffline,
  SyncStatus.failed => l10n.syncStatusHeadlineFailed,
};

String _heroSubtitle(AppLocalizations l10n, SyncStatusEvent e) {
  if (e.status == SyncStatus.syncing) return l10n.syncStatusHeroSyncing;
  final last = e.lastSuccessAt;
  if (last == null) return l10n.syncStatusSubtitleNeverSynced;
  return l10n.syncStatusSubtitleLastSynced(_relativeTime(l10n, last));
}

// ---------------------------------------------------------------------------
// Stat grid — three at-a-glance metrics
// ---------------------------------------------------------------------------

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.pending,
    required this.localTotal,
    required this.lastSyncAt,
  });

  final int? pending;
  final int? localTotal;
  final DateTime? lastSyncAt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);

    final pendingValue = pending == null ? '—' : '$pending';
    final pendingHasItems = (pending ?? 0) > 0;

    final localValue = localTotal == null ? '—' : '$localTotal';

    final lastSyncLabel = lastSyncAt == null
        ? l10n.syncStatusStatNever
        : _relativeTimeShort(l10n, lastSyncAt!);

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 360;
        final gap = wide ? 8.0 : 8.0;
        Widget tile(Widget w) => SizedBox(
          width: wide ? (c.maxWidth - gap * 2) / 3 : c.maxWidth,
          child: w,
        );
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            tile(
              _StatTile(
                icon: FLucideIcons.send,
                value: pendingValue,
                label: l10n.syncStatusStatPending,
                accent: pendingHasItems ? context.theme.colors.primary : null,
              ),
            ),
            tile(
              _StatTile(
                icon: FLucideIcons.database,
                value: localValue,
                label: l10n.syncStatusStatLocal,
              ),
            ),
            tile(
              _StatTile(
                icon: FLucideIcons.history,
                value: lastSyncLabel,
                label: l10n.syncStatusStatLastSync,
                accent: lastSyncAt == null ? semantic.warning : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.accent,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s12, AppSpacing.s12, AppSpacing.s12, AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: AppIconSizes.h18,
            color: accent ?? context.theme.colors.mutedForeground,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            value,
            style: context.theme.typography.lg.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: accent ?? context.theme.colors.foreground,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            label,
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
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
    final semantic = SemanticColors.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FLucideIcons.triangleAlert, color: semantic.danger, size: AppIconSizes.md),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message,
              style: context.theme.typography.xs.copyWith(
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

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.diagnostics});

  final SyncConflictDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FLucideIcons.arrowLeftRight, color: semantic.warning, size: AppIconSizes.md),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.syncStatusConflictsHeader,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.syncStatusConflictsLocalWins(diagnostics.localWins),
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
                if (diagnostics.ignoredRows > 0) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    l10n.syncStatusConflictsIgnored(diagnostics.ignoredRows),
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diagnostics card
// ---------------------------------------------------------------------------

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.event,
    required this.cursor,
    required this.deviceId,
    required this.apiBaseUrl,
  });

  final SyncStatusEvent event;
  final int? cursor;
  final String? deviceId;
  final String? apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      child: Column(
        children: [
          _Row(label: l10n.syncStatusDetailState, value: event.status.name),
          const FDivider(),
          _Row(
            label: l10n.syncStatusDetailUpdatedAt,
            value: _relativeTime(l10n, event.at),
          ),
          if (deviceId != null) ...[
            const FDivider(),
            _Row(
              label: l10n.syncStatusDetailDevice,
              value: _shortDeviceId(deviceId!),
              monospace: true,
            ),
          ],
          const FDivider(),
          _Row(
            label: l10n.syncStatusDetailCursor,
            value: (cursor == null || cursor == 0)
                ? l10n.syncStatusDetailCursorUnset
                : '#$cursor',
            monospace: cursor != null && cursor != 0,
          ),
          if (event.conflicts.remoteRows > 0) ...[
            const FDivider(),
            _Row(
              label: l10n.syncStatusDetailRemoteRows,
              value:
                  '${event.conflicts.appliedRows}/${event.conflicts.remoteRows}',
              monospace: true,
            ),
          ],
          if (apiBaseUrl != null) ...[
            const FDivider(),
            _Row(
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

// ---------------------------------------------------------------------------
// Local counts (debug)
// ---------------------------------------------------------------------------

class _LocalCountsCard extends StatelessWidget {
  const _LocalCountsCard({required this.counts});

  final LocalTableCounts? counts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (counts == null) {
      return const SoftCard(
        padding: EdgeInsets.all(AppSpacing.s12),
        child: Center(child: FCircularProgress()),
      );
    }

    Widget cell(String id) {
      final value = counts![id] ?? 0;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _localCountLabel(l10n, id),
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ),
            Text(
              '$value',
              style: context.theme.typography.sm.copyWith(
                color: value > 0
                    ? context.theme.colors.foreground
                    : context.theme.colors.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.s12, AppSpacing.s8, AppSpacing.s12, AppSpacing.s4),
            child: Text(
              l10n.syncStatusLocalCountsHeader,
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
                letterSpacing: 0.4,
              ),
            ),
          ),
          for (var i = 0; i < kFinanceLocalCountIds.length; i += 2)
            Row(
              children: [
                Expanded(child: cell(kFinanceLocalCountIds[i])),
                Expanded(
                  child: i + 1 < kFinanceLocalCountIds.length
                      ? cell(kFinanceLocalCountIds[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _localCountLabel(AppLocalizations l10n, String id) => switch (id) {
  'accounts_user' => l10n.syncStatusLocalAccountsUser,
  'accounts_system' => l10n.syncStatusLocalAccountsSystem,
  'journal_entries' => l10n.syncStatusLocalJournalEntries,
  'postings' => l10n.syncStatusLocalPostings,
  'assets' => l10n.syncStatusLocalAssets,
  'prices' => l10n.syncStatusLocalPrices,
  'liabilities' => l10n.syncStatusLocalLiabilities,
  'tags' => l10n.syncStatusLocalTags,
  _ => id,
};

// ---------------------------------------------------------------------------
// Status orb
// ---------------------------------------------------------------------------

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
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.palette.container,
          ),
          alignment: Alignment.center,
          child: Transform.scale(
            scale: pulse,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.palette.foreground,
              ),
              alignment: Alignment.center,
              child: Icon(
                _statusIcon(widget.status),
                size: AppIconSizes.xs,
                color: widget.palette.onForeground,
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _statusIcon(SyncStatus s) => switch (s) {
    SyncStatus.idle => FLucideIcons.cloud,
    SyncStatus.syncing => FLucideIcons.refreshCw,
    SyncStatus.online => FLucideIcons.cloudCheck,
    SyncStatus.offline => FLucideIcons.cloudOff,
    SyncStatus.failed => FLucideIcons.circleAlert,
  };
}

// ---------------------------------------------------------------------------
// Shared row + helpers
// ---------------------------------------------------------------------------

class _Row extends StatelessWidget {
  const _Row({
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
    final valueStyle =
        (monospace ? context.theme.typography.xs : context.theme.typography.sm)
            .copyWith(
              color: context.theme.colors.foreground,
              fontFeatures: monospace
                  ? const [FontFeature.tabularFigures()]
                  : null,
              fontFamily: monospace ? 'monospace' : null,
            );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: wrap
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
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
  final semantic = SemanticColors.of(context);
  return switch (s) {
    SyncStatus.idle => _StatusPalette(
      foreground: context.theme.colors.mutedForeground,
      onForeground: context.theme.colors.background,
      container: context.theme.colors.secondary,
    ),
    SyncStatus.syncing => _StatusPalette(
      foreground: context.theme.colors.primary,
      onForeground: context.theme.colors.primaryForeground,
      container: context.theme.colors.muted,
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

String _relativeTime(AppLocalizations l10n, DateTime ts) {
  final diff = DateTime.now().difference(ts);
  if (diff.inSeconds < 45) return l10n.syncStatusJustNow;
  if (diff.inMinutes < 60) return l10n.syncStatusMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.syncStatusHoursAgo(diff.inHours);
  return l10n.syncStatusDaysAgo(diff.inDays);
}

/// Compact form for the stat tile — drops the "ago" suffix to fit the
/// narrow column width without truncation.
String _relativeTimeShort(AppLocalizations l10n, DateTime ts) {
  final diff = DateTime.now().difference(ts);
  if (diff.inSeconds < 45) return l10n.syncStatusStatJustNow;
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}
