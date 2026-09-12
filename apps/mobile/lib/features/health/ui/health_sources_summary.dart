import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/formatters.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/health_series_providers.dart';
import '../data/providers.dart' as health_data;
import 'health_metric_presentation.dart';
import 'health_today_providers.dart';

/// Compact source status on Today; connection tools live in domain settings.
class HealthSourcesSummary extends ConsumerWidget {
  const HealthSourcesSummary({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(health_data.garminSyncControllerProvider);
    final previous = state is health_data.GarminSyncing
        ? state.previous
        : state;
    final dataAt = ref
        .watch(health_data.healthSourceDataSummaryProvider)
        .value
        ?.garminLatestAt;
    final label = switch (state) {
      health_data.GarminSyncing() => l.healthGarminSyncingBadge,
      health_data.GarminRestoring() => l.healthGarminRestoringBadge,
      health_data.GarminPendingMfa() => l.healthGarminVerifyBadge,
      _ => switch (previous) {
        health_data.GarminConnected(partial: true) => l.healthGarminPartialSync,
        health_data.GarminConnected(lastErrorCode: null) =>
          l.healthGarminConnected,
        health_data.GarminConnected() ||
        health_data.GarminError() => l.healthSourceSyncFailed,
        _ => l.healthGarminDisconnected,
      },
    };
    return AppGroupedSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const HealthPlatformSourceRow(),
          const AppGroupedDivider(
            indent: AppSpacing.s12,
            endIndent: AppSpacing.s12,
          ),
          _SourceRow(
            icon: FLucideIcons.watch,
            title: l.healthGarminTitle,
            status: label,
            dataAt: dataAt,
            onPress: () => context.push(SettingsRoutes.domainsHealth),
          ),
        ],
      ),
    );
  }
}

class HealthPlatformSourceRow extends ConsumerStatefulWidget {
  const HealthPlatformSourceRow({super.key, this.manage = false});
  final bool manage;
  @override
  ConsumerState<HealthPlatformSourceRow> createState() =>
      _HealthPlatformSourceRowState();
}

class _HealthPlatformSourceRowState
    extends ConsumerState<HealthPlatformSourceRow> {
  bool _running = false;
  Future<void> _sync() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final coordinator = await ref.read(
        health_data.healthRefreshCoordinatorProvider.future,
      );
      await coordinator.connectAndSyncPlatform();
      if (!mounted) return;
      ref
        ..invalidate(health_data.healthSyncStatusProvider)
        ..invalidate(health_data.healthPlatformStatusProvider)
        ..invalidate(health_data.healthSourceDataSummaryProvider)
        ..invalidate(healthTodaySnapshotProvider)
        ..invalidate(healthTrendSeriesProvider);
    } on Object {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).healthSyncFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final platform = ref.watch(health_data.healthPlatformStatusProvider);
    final persisted = ref.watch(health_data.healthSyncStatusProvider);
    final dataAt = ref
        .watch(health_data.healthSourceDataSummaryProvider)
        .value
        ?.platformLatestAt;
    final status = _running
        ? l.settingsDomainsHealthSyncRunning
        : platform.isLoading
        ? l.healthSourceChecking
        : platform.value?.available != true ||
              platform.value?.checkFailed == true
        ? l.healthSourceUnavailable
        : platform.value?.needsPermission == true
        ? l.healthSourcePermissionRequired
        : persisted?.ok == false
        ? l.healthSourceSyncFailed
        : l.healthSourceReady;
    return _SourceRow(
      icon: FLucideIcons.activity,
      title: l.healthKitTitle,
      status: status,
      dataAt: dataAt,
      onPress: widget.manage
          ? null
          : () => context.push(SettingsRoutes.domainsHealth),
      action: widget.manage && platform.value?.available == true
          ? FButton(
              variant: FButtonVariant.outline,
              mainAxisSize: MainAxisSize.min,
              onPress: _running ? null : _sync,
              child: Text(
                platform.value?.needsPermission == true
                    ? l.healthActivationAction
                    : l.healthGarminSync,
              ),
            )
          : null,
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.dataAt,
    this.onPress,
    this.action,
  });
  final IconData icon;
  final String title;
  final String status;
  final DateTime? dataAt;
  final VoidCallback? onPress;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: AppIconSizes.sm,
                color: context.theme.colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.rowTitleStyle),
                    const SizedBox(height: AppSpacing.s4),
                    Text(status, style: context.captionStyle),
                    if (dataAt != null)
                      Text(
                        l.healthSourceDataAt(
                          AppFormatters.relativeTime(
                            dataAt!,
                            justNow: l.aiChatRelativeJustNow,
                            minutesAgo: l.aiChatRelativeMinutesAgo,
                            hoursAgo: l.aiChatRelativeHoursAgo,
                            daysAgo: l.aiChatRelativeDaysAgo,
                            dateFallback: (d) => healthDateLabel(l, d),
                          ),
                        ),
                        style: context.microCaptionStyle,
                      ),
                  ],
                ),
              ),
              if (onPress != null)
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.xs,
                  color: context.theme.colors.mutedForeground,
                ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Align(alignment: AlignmentDirectional.centerEnd, child: action),
          ],
        ],
      ),
    );
    return onPress == null
        ? content
        : AppTappable(onPress: onPress, child: content);
  }
}
