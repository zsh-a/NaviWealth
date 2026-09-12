import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/health_series_providers.dart';
import '../data/providers.dart' as health_data;
import 'health_metric_presentation.dart';

class HealthSourceAttention extends ConsumerWidget {
  const HealthSourceAttention({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(healthClockProvider)();
    final platform = ref.watch(health_data.healthSyncStatusProvider);
    final state = ref.watch(health_data.garminSyncControllerProvider);
    final garmin = state is health_data.GarminSyncing ? state.previous : state;
    final platformAt = platform?.lastSuccessAt;
    final garminAt = switch (garmin) {
      health_data.GarminConnected(:final lastSyncAt) => lastSyncAt,
      _ => null,
    };
    final latestSyncAt = _latestDate(platformAt, garminAt);
    final sourceData = ref.watch(health_data.healthSourceDataSummaryProvider);
    final latestDataAt = _latestDate(
      sourceData.value?.platformLatestAt,
      sourceData.value?.garminLatestAt,
    );
    final l10n = AppLocalizations.of(context);
    final persistedPlatformFailure = platform?.ok == false;
    final garminFailure = switch (garmin) {
      health_data.GarminError() || health_data.GarminPendingMfa() => true,
      health_data.GarminConnected(:final lastErrorCode) =>
        lastErrorCode != null,
      _ => false,
    };
    final persistedFailureCount =
        (persistedPlatformFailure ? 1 : 0) + (garminFailure ? 1 : 0);
    if (persistedFailureCount > 0) {
      final failureCount = persistedFailureCount;
      return AppStatusBanner(
        message: l10n.healthRefreshPartialFailure(failureCount),
        details:
            persistedPlatformFailure &&
                _isHealthPermissionError(platform?.errorCode)
            ? l10n.healthSyncPermissionDenied
            : latestDataAt != null
            ? _isHealthDataStale(latestDataAt, now)
                  ? l10n.healthRefreshStale(
                      healthRelativeTime(l10n, latestDataAt),
                    )
                  : l10n.healthRefreshFresh(
                      healthRelativeTime(l10n, latestDataAt),
                    )
            : latestSyncAt == null
            ? l10n.healthRefreshPullHint
            : l10n.healthRefreshFresh(healthRelativeTime(l10n, latestSyncAt)),
        kind: AppStatusKind.warning,
        icon: FLucideIcons.circleAlert,
        compact: true,
      );
    }
    if (latestDataAt == null) return const SizedBox.shrink();
    final stale = _isHealthDataStale(latestDataAt, now);
    // A successful, recent sync is already implicit in the source details
    // and recovery freshness badge. Keep this module reserved for states
    // that need attention so Today does not spend a full row repeating
    // healthy status.
    if (!stale) return const SizedBox.shrink();
    return AppStatusBanner(
      message: l10n.healthRefreshStale(healthRelativeTime(l10n, latestDataAt)),
      details: l10n.healthRefreshPullHint,
      kind: AppStatusKind.warning,
      icon: FLucideIcons.clockAlert,
      compact: true,
    );
  }
}

DateTime? _latestDate(DateTime? left, DateTime? right) {
  if (left == null) return right;
  if (right == null) return left;
  return left.isAfter(right) ? left : right;
}

bool _isHealthDataStale(DateTime at, DateTime now) =>
    now.toUtc().difference(at.toUtc()) > const Duration(hours: 36);

bool _isHealthPermissionError(String? errorCode) {
  final normalized = errorCode?.toLowerCase() ?? '';
  return normalized.contains('permission') || normalized.contains('权限');
}

String healthRelativeTime(AppLocalizations l10n, DateTime when) =>
    AppFormatters.relativeTime(
      when,
      justNow: l10n.aiChatRelativeJustNow,
      minutesAgo: l10n.aiChatRelativeMinutesAgo,
      hoursAgo: l10n.aiChatRelativeHoursAgo,
      daysAgo: l10n.aiChatRelativeDaysAgo,
      dateFallback: (d) => healthDateLabel(l10n, d),
    );
