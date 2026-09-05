/// HealthOS Today surface (`docs/domains/healthos-domain.md` §8, D-2.5b
/// follow-up).
///
/// Renders HealthKit/Garmin sync status, recovery, key metrics, weekly
/// summary. Trend and Plan now have MVP
/// surfaces; Today stays the dense operational entry point.
///
/// Chrome matches the rest of LifeOS (`docs/architecture/lifeos-shell.md` §3): a
/// headerless cockpit root (`ShellCanvasScaffold`) with the task
/// header ([HealthGreetingHeader]) inside the brief — the same
/// pattern as FinanceOS Today — plus `SoftCard` surfaces and
/// `context.theme` tokens — never Material `Scaffold` / `Theme.of` —
/// so HealthOS reads as the same app as Finance / Knowledge.
library;

import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/format/formatters.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../data/health_metric_source.dart';
import '../data/health_sync_status.dart';
import '../data/providers.dart' as health_data;
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'body_measurement_entry_sheet.dart';
import 'garmin_account_bind_sheet.dart';
import 'garmin_sync_status_card.dart';
import 'health_greeting_header.dart';
import 'health_metric_colors.dart';
import 'health_today_providers.dart';
import 'health_trend_page.dart' show healthTrendPath;
import 'plan_actions.dart';
import 'recovery_verdict.dart';

part 'metric_grid.dart';
part 'metric_grid_cards.dart';
part 'metric_grid_primitives.dart';
part 'recovery_hero.dart';
part 'weekly_summary_panel.dart';

class HealthTodayPage extends ConsumerStatefulWidget {
  const HealthTodayPage({super.key});

  @override
  ConsumerState<HealthTodayPage> createState() => _HealthTodayPageState();
}

class _HealthTodayPageState extends ConsumerState<HealthTodayPage> {
  health_data.HealthRefreshResult? _lastRefresh;

  Future<void> _refresh() async {
    final coordinator = await ref.read(
      health_data.healthRefreshCoordinatorProvider.future,
    );
    final result = await coordinator.refreshConnectedSources();
    if (mounted) setState(() => _lastRefresh = result);
    _invalidateHealthSurfaces(ref);
    await ref.read(healthTodaySnapshotProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final hasData = ref.watch(healthHasAnyDataProvider);
    final dataReady = hasData.value == true;
    final resolving = hasData.isLoading && !hasData.hasValue;
    final error = hasData.error;
    final stage = PageSkeletonShell<bool>(
      skeleton: const _HealthTodayStageSkeleton(),
      isLoading: resolving,
      child: error != null
          ? kDefaultError(
              context,
              error,
              hasData.stackTrace ?? StackTrace.current,
              onRetry: () => ref.invalidate(healthHasAnyDataProvider),
            )
          : dataReady
          ? const FadeSlideIn(child: _RecoveryHero())
          : const _HealthActivationCard(),
    );
    // The task header owns actions; DomainTabsShell supplies global overlays.
    return ShellCanvasScaffold(
      childPad: false,
      child: ShellTabPause(
        routePath: HealthRoutes.today,
        child: BriefScaffold(
          padding: shellTabContentPadding(context),
          onRefresh: _refresh,
          greeting: const HealthGreetingHeader(),
          stage: stage,
          stickyBuilder: dataReady
              ? (context, progress) =>
                    _HealthRecoveryStickyBar(progress: progress)
              : null,
          summaryTiles: dataReady
              ? staggeredSummaryTiles([
                  AdaptiveSummaryTile(
                    role: AdaptiveSummaryTileRole.continuous,
                    child: _HealthDataFreshnessBanner(
                      lastRefresh: _lastRefresh,
                    ),
                  ),
                  const AdaptiveSummaryTile(
                    role: AdaptiveSummaryTileRole.featured,
                    child: _MetricGrid(),
                  ),
                  const AdaptiveSummaryTile(
                    role: AdaptiveSummaryTileRole.supporting,
                    child: _SourcesSection(),
                  ),
                  const AdaptiveSummaryTile(
                    role: AdaptiveSummaryTileRole.continuous,
                    child: _WeeklySummaryPanel(),
                  ),
                ])
              // The activation card already exposes the three first-run
              // source actions. Repeating the same collapsed source section
              // below it makes the empty state feel like two onboarding
              // surfaces instead of one clear next step.
              : const <AdaptiveSummaryTile>[],
        ),
      ),
    );
  }
}

/// Mirrors the recovery hero while `healthHasAnyDataProvider` resolves, so
/// the stage swaps to real data without reflowing the brief.
class _HealthTodayStageSkeleton extends StatelessWidget {
  const _HealthTodayStageSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 36, height: 36, radius: AppRadius.sm),
              SizedBox(width: AppSpacing.s12),
              Expanded(child: SkeletonBox(height: 14)),
              SizedBox(width: AppSpacing.s12),
              SkeletonBox(width: 48, height: 28, radius: AppRadius.sm),
            ],
          ),
          SizedBox(height: AppSpacing.s16),
          SkeletonBox(width: 200, height: 30, radius: AppRadius.sm),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(height: 14),
          SizedBox(height: AppSpacing.s4),
          SkeletonBox(width: 240, height: 14),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(width: 160, height: 22, radius: AppRadius.full),
        ],
      ),
    );
  }
}

class _HealthActivationCard extends ConsumerStatefulWidget {
  const _HealthActivationCard();

  @override
  ConsumerState<_HealthActivationCard> createState() =>
      _HealthActivationCardState();
}

class _HealthActivationCardState extends ConsumerState<_HealthActivationCard> {
  bool _running = false;
  String? _error;

  Future<void> _activatePlatform() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final coordinator = await ref.read(
        health_data.healthRefreshCoordinatorProvider.future,
      );
      final result = await coordinator.connectAndSyncPlatform();
      if (!result.synced) {
        if (mounted) {
          setState(() {
            _error = result.errorCode == 'health-platform-permission-denied'
                ? AppLocalizations.of(context).healthSyncPermissionDenied
                : AppLocalizations.of(context).healthSyncFailed;
          });
        }
        return;
      }
      _invalidateHealthSurfaces(ref);
      await ref.read(healthTodaySnapshotProvider.future);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _activateGarmin() async {
    await showGarminAccountBindSheet(context: context);
    if (!mounted ||
        ref.read(health_data.garminSyncControllerProvider)
            is! health_data.GarminConnected) {
      return;
    }
    setState(() => _running = true);
    try {
      await ref
          .read(health_data.garminSyncControllerProvider.notifier)
          .syncNow();
      _invalidateHealthSurfaces(ref);
      await ref.read(healthTodaySnapshotProvider.future);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _recordManually() async {
    final saved = await showBodyMeasurementEntrySheet(
      context: context,
      initialKind: HealthMetricKind.weight,
    );
    if (saved == true) _invalidateHealthSurfaces(ref);
  }

  @override
  Widget build(BuildContext context) {
    final hasData = ref.watch(healthHasAnyDataProvider);
    return hasData.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (value) {
        if (value) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        return SoftCard(
          level: SoftCardLevel.raised,
          padding: AppPageRhythm.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppMetricHeader(
                icon: FLucideIcons.heartPulse,
                title: l10n.healthActivationTitle,
                color: context.appTheme.status.info.fg,
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(l10n.healthActivationBody, style: context.captionStyle),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.s8),
                Text(
                  _error!,
                  style: context.captionStyle.copyWith(
                    color: context.appTheme.status.danger.fg,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s12),
              AppAdaptiveActionMenu(
                title: l10n.healthActivationTitle,
                subtitle: l10n.healthActivationBody,
                actions: [
                  AppAdaptiveAction(
                    icon: FLucideIcons.heartPulse,
                    title: l10n.healthActivationAction,
                    onPress: _activatePlatform,
                  ),
                  AppAdaptiveAction(
                    icon: FLucideIcons.watch,
                    title: l10n.healthActivationGarminAction,
                    onPress: _activateGarmin,
                  ),
                  AppAdaptiveAction(
                    icon: FLucideIcons.pencil,
                    title: l10n.healthActivationManualAction,
                    onPress: _recordManually,
                  ),
                ],
                triggerBuilder: (context, openMenu, focusNode) => SizedBox(
                  width: double.infinity,
                  child: FButton(
                    focusNode: focusNode,
                    onPress: _running ? null : openMenu,
                    child: _running
                        ? const FCircularProgress()
                        : Text(l10n.healthActivationTitle),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HealthDataFreshnessBanner extends ConsumerWidget {
  const _HealthDataFreshnessBanner({required this.lastRefresh});

  final health_data.HealthRefreshResult? lastRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(health_data.healthSyncStatusProvider);
    final garmin = ref.watch(health_data.garminSyncControllerProvider);
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
    final failures = lastRefresh?.failedCount ?? 0;
    final persistedPlatformFailure = platform?.ok == false;
    final garminFailure = switch (garmin) {
      health_data.GarminError() => true,
      health_data.GarminConnected(:final lastErrorCode) =>
        lastErrorCode != null,
      _ => false,
    };
    final persistedFailureCount =
        (persistedPlatformFailure ? 1 : 0) + (garminFailure ? 1 : 0);
    if (failures > 0 || persistedFailureCount > 0) {
      final failureCount = failures > 0 ? failures : persistedFailureCount;
      return AppStatusBanner(
        message: l10n.healthRefreshPartialFailure(failureCount),
        details:
            persistedPlatformFailure &&
                _isHealthPermissionError(platform?.errorCode)
            ? l10n.healthSyncPermissionDenied
            : latestDataAt != null
            ? _isHealthDataStale(latestDataAt)
                  ? l10n.healthRefreshStale(_ago(l10n, latestDataAt))
                  : l10n.healthRefreshFresh(_ago(l10n, latestDataAt))
            : latestSyncAt == null
            ? l10n.healthRefreshPullHint
            : l10n.healthRefreshFresh(_ago(l10n, latestSyncAt)),
        kind: AppStatusKind.warning,
        icon: FLucideIcons.circleAlert,
        compact: true,
      );
    }
    if (latestDataAt == null) return const SizedBox.shrink();
    final stale =
        DateTime.now().toUtc().difference(latestDataAt.toUtc()) >
        const Duration(hours: 36);
    // A successful, recent sync is already implicit in the source details
    // and recovery freshness badge. Keep this module reserved for states
    // that need attention so Today does not spend a full row repeating
    // healthy status.
    if (!stale) return const SizedBox.shrink();
    return AppStatusBanner(
      message: l10n.healthRefreshStale(_ago(l10n, latestDataAt)),
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

bool _isHealthDataStale(DateTime at) =>
    DateTime.now().toUtc().difference(at.toUtc()) > const Duration(hours: 36);

bool _isHealthPermissionError(String? errorCode) {
  final normalized = errorCode?.toLowerCase() ?? '';
  return normalized.contains('permission') || normalized.contains('权限');
}

void _invalidateHealthSurfaces(WidgetRef ref) {
  ref.invalidate(health_data.healthSyncStatusProvider);
  ref.invalidate(health_data.healthPlatformStatusProvider);
  ref.invalidate(health_data.healthSourceDataSummaryProvider);
  ref.invalidate(healthTodaySnapshotProvider);
}

/// Sticky residual for the recovery stage — icon + verdict + score.
class _HealthRecoveryStickyBar extends ConsumerWidget {
  const _HealthRecoveryStickyBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final recovery = ref.watch(recoverySignalProvider);

    final (verdict, scoreText) = recovery.maybeWhen(
      data: (out) {
        final verdict = out?['verdict']?.toString() ?? 'insufficient_data';
        final score = out?['score'];
        return (verdict, score == null ? null : '$score');
      },
      orElse: () => ('insufficient_data', null),
    );
    final accent = RecoveryVerdict.color(verdict, colors);

    return AppCollapsedSummaryBar(
      progress: progress,
      child: AppCollapsedSummaryContent(
        leading: AppIconTile(
          icon: RecoveryVerdict.icon(verdict),
          color: accent,
          size: 28,
          iconSize: AppIconSizes.sm,
          radius: AppRadius.sm,
          backgroundOpacity: AppOpacity.subtle,
          foregroundOpacity: 1,
        ),
        label: RecoveryVerdict.label(verdict, l10n),
        labelStyle: context.labelStyle.copyWith(color: accent),
        value: scoreText == null
            ? null
            : Text(
                scoreText,
                style: TypographyTokens.numericTitleStrong.copyWith(
                  color: accent,
                ),
              ),
      ),
    );
  }
}

/// Collapsed by default — data plumbing is secondary to today's story.
class _SourcesSection extends StatefulWidget {
  const _SourcesSection();

  @override
  State<_SourcesSection> createState() => _SourcesSectionState();
}

class _SourcesSectionState extends State<_SourcesSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDisclosureHeader(
          title: l10n.healthSourcesTitle,
          subtitle: l10n.healthSourcesSubtitle,
          expanded: _open,
          onToggle: () => setState(() => _open = !_open),
        ),
        AnimatedSizeFade(
          visible: _open,
          child: const Padding(
            padding: EdgeInsets.only(top: AppSpacing.s8),
            child: _DataSourcePanel(),
          ),
        ),
      ],
    );
  }
}

class _DataSourcePanel extends StatelessWidget {
  const _DataSourcePanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Breakpoints.contentThreeColumn) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HealthKitSyncCard(),
              SizedBox(height: AppSpacing.s8),
              GarminSyncStatusCard(showActions: false),
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _HealthKitSyncCard()),
            SizedBox(width: AppSpacing.s8),
            Expanded(child: GarminSyncStatusCard(showActions: false)),
          ],
        );
      },
    );
  }
}

class _HealthKitSyncCard extends ConsumerWidget {
  const _HealthKitSyncCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final optIns = ref.watch(core_auth.domainOptInsProvider).value;
    final enabled = optIns?.contains(DomainScope.health) ?? false;
    final persisted = ref.watch(health_data.healthSyncStatusProvider);
    final platformStatus = ref.watch(health_data.healthPlatformStatusProvider);
    final sourceData = ref.watch(health_data.healthSourceDataSummaryProvider);
    final latestDataAt = sourceData.value?.platformLatestAt;

    final badge = AppBadge(
      label: _healthKitBadge(
        l10n,
        enabled,
        platformStatus: platformStatus,
        persisted: persisted,
      ),
      tone: _healthKitBadgeTone(
        enabled,
        platformStatus: platformStatus,
        persisted: persisted,
      ),
      size: AppBadgeSize.compact,
    );
    return SoftCard(
      level: SoftCardLevel.raised,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppMetricHeader(
            icon: enabled ? FLucideIcons.activity : FLucideIcons.circleOff,
            title: l10n.healthKitTitle,
            color: _healthKitColor(
              context,
              enabled,
              platformStatus: platformStatus,
              persisted: persisted,
            ),
            showChevron: false,
            trailing: Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.s8),
              child: badge,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            _healthKitText(
              l10n,
              enabled,
              platformStatus: platformStatus,
              persisted: persisted,
            ),
            style: context.captionStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (_healthKitMetadata(
                l10n,
                platformStatus: platformStatus,
                persisted: persisted,
                latestDataAt: latestDataAt,
              )
              case final String metadata)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: Text(
                metadata,
                style: context.microCaptionStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Color _healthKitColor(
    BuildContext context,
    bool enabled, {
    required AsyncValue<health_data.HealthPlatformStatus> platformStatus,
    required HealthSyncStatus? persisted,
  }) {
    final colors = context.theme.colors;
    if (!enabled) return colors.mutedForeground;
    final status = platformStatus.value;
    if (status?.needsPermission == true) {
      return context.appTheme.status.warning.fg;
    }
    if (_hasSyncFailure(persisted)) return colors.destructive;
    if (status?.ready == true) return context.appTheme.status.success.fg;
    return colors.mutedForeground;
  }

  String _healthKitBadge(
    AppLocalizations l10n,
    bool enabled, {
    required AsyncValue<health_data.HealthPlatformStatus> platformStatus,
    required HealthSyncStatus? persisted,
  }) {
    if (!enabled) return l10n.healthNotEnabled;
    if (platformStatus.isLoading) return l10n.healthSourceChecking;
    final status = platformStatus.value;
    if (status == null || !status.available || status.checkFailed) {
      return l10n.healthSourceUnavailable;
    }
    if (status.needsPermission) return l10n.healthSourcePermissionRequired;
    if (_hasSyncFailure(persisted)) return l10n.healthSourceSyncFailed;
    return l10n.healthSourceReady;
  }

  AppBadgeTone _healthKitBadgeTone(
    bool enabled, {
    required AsyncValue<health_data.HealthPlatformStatus> platformStatus,
    required HealthSyncStatus? persisted,
  }) {
    if (!enabled) return AppBadgeTone.neutral;
    if (platformStatus.isLoading) return AppBadgeTone.info;
    final status = platformStatus.value;
    if (status == null || !status.available || status.checkFailed) {
      return AppBadgeTone.neutral;
    }
    if (status.needsPermission) return AppBadgeTone.warning;
    if (_hasSyncFailure(persisted)) return AppBadgeTone.error;
    return AppBadgeTone.success;
  }

  bool _hasSyncFailure(HealthSyncStatus? persisted) => persisted?.ok == false;

  String _healthKitText(
    AppLocalizations l10n,
    bool enabled, {
    required AsyncValue<health_data.HealthPlatformStatus> platformStatus,
    required HealthSyncStatus? persisted,
  }) {
    if (!enabled) return l10n.healthNotEnabled;
    if (platformStatus.isLoading) return l10n.healthSourceChecking;
    final status = platformStatus.value;
    if (status == null || !status.available || status.checkFailed) {
      return l10n.healthSourceUnavailable;
    }
    if (status.needsPermission) return l10n.healthSourcePermissionRequired;
    if (persisted == null) return l10n.healthSyncReady;
    if (!persisted.ok) return _syncFailureText(l10n, persisted.errorCode);
    return l10n.healthSourceReady;
  }

  String _syncFailureText(AppLocalizations l10n, String? errorCode) {
    final normalized = errorCode?.toLowerCase() ?? '';
    if (normalized.contains('permission') || normalized.contains('权限')) {
      return l10n.healthSyncPermissionDenied;
    }
    return l10n.healthSyncFailed;
  }

  String? _healthKitMetadata(
    AppLocalizations l10n, {
    required AsyncValue<health_data.HealthPlatformStatus> platformStatus,
    required HealthSyncStatus? persisted,
    required DateTime? latestDataAt,
  }) {
    final details = <String>[];
    final status = persisted;
    if (status?.ok == false) {
      final attemptedAt = status?.completedAt;
      if (attemptedAt != null) {
        details.add(l10n.healthSourceLastAttempt(_ago(l10n, attemptedAt)));
      }
      if (status?.lastSuccessAt != null) {
        details.add(
          l10n.healthSourceLastSuccess(_ago(l10n, status!.lastSuccessAt!)),
        );
      }
    } else if (status != null) {
      details.add(l10n.healthSourceLastSync(_ago(l10n, status.completedAt)));
    }
    if (latestDataAt != null) {
      details.add(l10n.healthSourceDataAt(_ago(l10n, latestDataAt)));
    } else if (platformStatus.value?.ready == true && details.isEmpty) {
      details.add(l10n.healthSourceNoData);
    }
    if (details.isEmpty) return null;
    return details.join(' · ');
  }
}
