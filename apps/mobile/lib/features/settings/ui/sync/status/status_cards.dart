part of '../sync_status_page.dart';

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.event,
    required this.now,
    required this.onSyncNow,
  });

  final SyncStatusEvent event;
  final DateTime now;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = _palette(context, event.status);
    final syncing = event.status == SyncStatus.syncing;

    return SoftCard.flat(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s20,
        AppSpacing.s12,
        AppSpacing.s20,
      ),
      child: Row(
        children: [
          _StatusOrb(palette: palette, status: event.status),
          const SizedBox(width: AppSpacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusHeadline(l10n, event.status),
                  style: context.titleLabelStyle,
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  _heroSubtitle(l10n, event, now),
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          if (onSyncNow != null && !syncing) ...[
            const SizedBox(width: AppSpacing.s8),
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

String _heroSubtitle(AppLocalizations l10n, SyncStatusEvent e, DateTime now) {
  if (e.status == SyncStatus.syncing) return l10n.syncStatusHeroSyncing;
  final last = e.lastSuccessAt;
  if (last == null) return l10n.syncStatusSubtitleNeverSynced;
  return l10n.syncStatusSubtitleLastSynced(_relativeTime(l10n, last, now));
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.pending,
    required this.localTotal,
    required this.lastSyncAt,
    required this.now,
  });

  final int? pending;
  final int? localTotal;
  final DateTime? lastSyncAt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);

    final pendingValue = pending == null ? '\u2014' : '$pending';
    final pendingHasItems = (pending ?? 0) > 0;

    final localValue = localTotal == null ? '\u2014' : '$localTotal';

    final lastSyncLabel = lastSyncAt == null
        ? l10n.syncStatusStatNever
        : _relativeTimeShort(l10n, lastSyncAt!, now);

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 360;
        const gap = AppSpacing.s8;
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
    return SoftCard.flat(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.s12,
      ),
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
            style: context.titleLabelStyle.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: accent ?? context.theme.colors.foreground,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(label, style: context.captionStyle),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final semantic = SemanticColors.of(context);
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FLucideIcons.triangleAlert,
            color: semantic.danger,
            size: AppIconSizes.md,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              message,
              style: context.captionStyle.copyWith(
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
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FLucideIcons.arrowLeftRight,
            color: semantic.warning,
            size: AppIconSizes.md,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.syncStatusConflictsHeader, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.syncStatusConflictsLocalWins(diagnostics.localWins),
                  style: context.captionStyle,
                ),
                if (diagnostics.ignoredRows > 0) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    l10n.syncStatusConflictsIgnored(diagnostics.ignoredRows),
                    style: context.captionStyle,
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

class _StabilityCard extends StatelessWidget {
  const _StabilityCard({required this.report});

  final SyncStabilityReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    final (icon, color, title) = switch (report.gateStatus) {
      SyncStabilityGateStatus.passing => (
        FLucideIcons.circleCheck,
        semantic.success,
        l10n.syncStabilityPassing,
      ),
      SyncStabilityGateStatus.failing => (
        FLucideIcons.triangleAlert,
        semantic.danger,
        l10n.syncStabilityFailing,
      ),
      SyncStabilityGateStatus.insufficientData => (
        FLucideIcons.clock,
        semantic.warning,
        l10n.syncStabilityCollecting,
      ),
    };
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: AppIconSizes.md),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.syncStabilityWindow(
                    report.successfulCycles,
                    report.samples.length,
                    report.observedDuration.inDays,
                  ),
                  style: context.captionStyle,
                ),
                const SizedBox(height: AppSpacing.s6),
                Wrap(
                  spacing: AppSpacing.s12,
                  runSpacing: AppSpacing.s4,
                  children: [
                    Text(
                      l10n.syncStabilitySuccessRate(
                        _syncPercentage(report.successRate),
                      ),
                      style: context.captionLabelStyle.copyWith(color: color),
                    ),
                    Text(
                      l10n.syncStabilityFatal(report.fatalFailures),
                      style: context.captionStyle,
                    ),
                    Text(
                      l10n.syncStabilityResetFailures(
                        report.generationResetFailures,
                      ),
                      style: context.captionStyle,
                    ),
                    if (report.recoveredCycles > 0)
                      Text(
                        l10n.syncStabilityRecoveries(report.recoveredCycles),
                        style: context.captionStyle,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int _syncPercentage(double value) => (value * 100).round().clamp(0, 100);
