part of '../sync_status_page.dart';

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
    duration: Motion.shimmerCycle,
  );
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _StatusOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _syncAnimation();
  }

  void _syncAnimation() {
    final shouldRun =
        widget.status == SyncStatus.syncing &&
        AppMotionPolicy.isEnabled(context, role: AppMotionRole.status);
    if (shouldRun == _running) return;
    _running = shouldRun;
    if (shouldRun) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl
        ..stop()
        ..value = 0;
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
        (monospace
                ? context.theme.typography.body.xs
                : context.theme.typography.body.sm)
            .copyWith(
              color: context.theme.colors.foreground,
              fontFeatures: monospace
                  ? const [FontFeature.tabularFigures()]
                  : null,
              fontFamily: monospace ? 'monospace' : null,
            );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        crossAxisAlignment: wrap
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: AppControlWidths.detailLabel,
            child: Text(label, style: context.captionStyle),
          ),
          Expanded(
            child: Text(value, style: valueStyle, maxLines: wrap ? null : 1),
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
  return '${id.substring(0, 8)}\u2026${id.substring(id.length - 4)}';
}

String _relativeTime(AppLocalizations l10n, DateTime ts, DateTime now) {
  final diff = now.difference(ts);
  if (diff.inSeconds < 45) return l10n.syncStatusJustNow;
  if (diff.inMinutes < 60) return l10n.syncStatusMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.syncStatusHoursAgo(diff.inHours);
  return l10n.syncStatusDaysAgo(diff.inDays);
}

/// Compact form for the stat tile: drops the "ago" suffix to fit the
/// narrow column width without truncation.
String _relativeTimeShort(AppLocalizations l10n, DateTime ts, DateTime now) {
  final diff = now.difference(ts);
  if (diff.inSeconds < 45) return l10n.syncStatusStatJustNow;
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}
