/// HealthOS Today surface (`docs/domains/healthos-domain.md` §8, D-2.5b
/// follow-up).
///
/// Renders HealthKit/Garmin sync status, recovery, key metrics, weekly
/// summary. Trend and Plan now have MVP
/// surfaces; Today stays the dense operational entry point.
///
/// Chrome matches the rest of LifeOS (`docs/architecture/lifeos-shell.md` §3): a
/// headerless cockpit root (`ShellCanvasScaffold`) with the editorial
/// greeting header ([HealthGreetingHeader]) inside the brief — the same
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
import '../data/health_sync_service.dart';
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
    // Headerless cockpit root, same as FinanceOS Today: the editorial
    // greeting ([HealthGreetingHeader]) replaces the static page title and
    // hosts the injected shell chrome via [ShellActionRow]. Global chrome
    // (sync strip, undo banner) is injected by DomainTabsShell.
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
                  const AdaptiveSummaryTile(child: _WeeklySummaryPanel()),
                ])
              : staggeredSummaryTiles(const [
                  AdaptiveSummaryTile(
                    role: AdaptiveSummaryTileRole.continuous,
                    child: _SourcesSection(),
                  ),
                ]),
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
    final latest = _latestDate(platformAt, garminAt);
    if (latest == null && lastRefresh == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final failures = lastRefresh?.failedCount ?? 0;
    if (failures > 0) {
      return AppStatusBanner(
        message: l10n.healthRefreshPartialFailure(failures),
        details: latest == null
            ? l10n.healthRefreshPullHint
            : l10n.healthRefreshFresh(_ago(l10n, latest)),
        kind: AppStatusKind.warning,
        icon: FLucideIcons.circleAlert,
        compact: true,
      );
    }
    if (latest == null) return const SizedBox.shrink();
    final stale =
        DateTime.now().toUtc().difference(latest.toUtc()) >
        const Duration(hours: 36);
    if (!stale) {
      return AppStatusLine(
        message: l10n.healthRefreshFresh(_ago(l10n, latest)),
        icon: FLucideIcons.refreshCw,
      );
    }
    return AppStatusBanner(
      message: l10n.healthRefreshStale(_ago(l10n, latest)),
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

void _invalidateHealthSurfaces(WidgetRef ref) {
  ref.invalidate(health_data.healthSyncStatusProvider);
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
              GarminSyncStatusCard(),
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _HealthKitSyncCard()),
            SizedBox(width: AppSpacing.s8),
            Expanded(child: GarminSyncStatusCard()),
          ],
        );
      },
    );
  }
}

class _HealthKitSyncCard extends ConsumerStatefulWidget {
  const _HealthKitSyncCard();

  @override
  ConsumerState<_HealthKitSyncCard> createState() => _HealthKitSyncCardState();
}

class _HealthKitSyncCardState extends ConsumerState<_HealthKitSyncCard> {
  bool _syncing = false;
  HealthSyncResult? _lastResult;

  Future<void> _syncHealthKit() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final service = await ref.read(
        health_data.healthSyncServiceProvider.future,
      );
      if (!await service.hasPermissions()) {
        final granted = await service.requestPermissions();
        if (!granted) {
          if (!mounted) return;
          setState(() {
            _lastResult = HealthSyncResult.skipped(
              startedAt: DateTime.now().toUtc(),
              errorMessage: AppLocalizations.of(
                context,
              ).healthSyncPermissionDenied,
            );
          });
          await service.recordResult(_lastResult!);
          ref.invalidate(health_data.healthSyncStatusProvider);
          return;
        }
      }
      final result = await service.syncRange();
      if (!mounted) return;
      setState(() => _lastResult = result);
      ref.invalidate(health_data.healthSyncStatusProvider);
      ref.invalidate(healthTodaySnapshotProvider);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final optIns = ref.watch(core_auth.domainOptInsProvider).value;
    final enabled = optIns?.contains(DomainScope.health) ?? false;
    final persisted = ref.watch(health_data.healthSyncStatusProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactAction = constraints.maxWidth < Breakpoints.compactContent;
        return SoftCard(
          level: SoftCardLevel.raised,
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Row(
            children: [
              AppIconTile(
                icon: enabled ? FLucideIcons.activity : FLucideIcons.circleOff,
                color: _healthKitColor(enabled),
                size: 32,
                iconSize: AppIconSizes.h18,
                backgroundOpacity: AppOpacity.whisper,
                foregroundOpacity: AppOpacity.strong,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.healthKitTitle,
                      style: context.labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      _healthKitText(l10n, enabled, persisted),
                      style: context.captionStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              if (compactAction)
                AppIconButton(
                  icon: FLucideIcons.refreshCw,
                  onPress: enabled ? _syncHealthKit : null,
                  tooltip: l10n.healthSyncAction,
                  surface: AppIconButtonSurface.softMuted,
                  size: 40,
                  iconSize: AppIconSizes.xs,
                  busy: _syncing,
                )
              else if (_syncing)
                const SizedBox(
                  width: AppIconSizes.sm,
                  height: AppIconSizes.sm,
                  child: FCircularProgress(),
                )
              else
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: enabled ? _syncHealthKit : null,
                  prefix: const Icon(
                    FLucideIcons.refreshCw,
                    size: AppIconSizes.xs,
                  ),
                  child: Text(l10n.healthSyncAction),
                ),
            ],
          ),
        );
      },
    );
  }

  Color _healthKitColor(bool enabled) {
    final colors = context.theme.colors;
    if (!enabled) return colors.mutedForeground;
    final result = _lastResult;
    if (_syncing) return colors.primary;
    if (result == null) {
      final persisted = ref.read(health_data.healthSyncStatusProvider);
      if (persisted == null) return colors.mutedForeground;
      return persisted.ok ? colors.primary : colors.destructive;
    }
    return result.ok ? colors.primary : colors.destructive;
  }

  String _healthKitText(
    AppLocalizations l10n,
    bool enabled,
    HealthSyncStatus? persisted,
  ) {
    if (!enabled) return l10n.healthNotEnabled;
    if (_syncing) return l10n.healthSyncingData;
    final result = _lastResult;
    if (result == null) {
      if (persisted == null) return l10n.healthSyncReady;
      if (!persisted.ok) return l10n.healthSyncFailed;
      return '${l10n.healthSyncResult('${persisted.unchanged}', '${persisted.upserted}')} · ${_ago(l10n, persisted.completedAt)}';
    }
    if (result.ok) {
      return l10n.healthSyncResult('${result.unchanged}', '${result.upserted}');
    }
    return result.errorMessage ?? l10n.healthSyncFailed;
  }
}
