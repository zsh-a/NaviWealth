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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../composition/health_trend_location.dart';
import '../data/health_series.dart';
import '../data/providers.dart' as health_data;
import '../domain/health_metric_kind.dart';
import 'body_measurement_entry_sheet.dart';
import 'garmin_account_bind_sheet.dart';
import 'garmin_foreground_refresh_scope.dart';
import 'health_greeting_header.dart';
import 'health_metric_colors.dart';
import 'health_metric_presentation.dart';
import 'health_series_chart.dart';
import 'health_source_attention.dart';
import 'health_sources_summary.dart';
import 'health_today_providers.dart';
import 'plan_actions.dart';
import 'recovery_verdict.dart';

part 'metric_grid.dart';
part 'recovery_hero.dart';
part 'weekly_summary_panel.dart';

class HealthTodayPage extends ConsumerStatefulWidget {
  const HealthTodayPage({super.key});

  @override
  ConsumerState<HealthTodayPage> createState() => _HealthTodayPageState();
}

class _HealthTodayPageState extends ConsumerState<HealthTodayPage> {
  Future<void> _refresh() async {
    final coordinator = await ref.read(
      health_data.healthRefreshCoordinatorProvider.future,
    );
    await coordinator.refreshConnectedSources();
    if (!mounted) return;
    _invalidateHealthSurfaces(ref);
    await ref.read(healthTodaySnapshotProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final hasData = ref.watch(healthHasAnyDataProvider);
    final dataReady = hasData.value == true;
    final hasRecovery =
        ref.watch(healthHasRecoveryInputsProvider).value == true;
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
          ? hasRecovery
                ? const FadeSlideIn(child: _RecoveryHero())
                : const _MetricGrid()
          : const _HealthActivationCard(),
    );
    // The task header owns actions; DomainTabsShell supplies global overlays.
    return ShellCanvasScaffold(
      childPad: false,
      child: ShellTabPause(
        routePath: HealthRoutes.today,
        child: GarminForegroundRefreshScope(
          child: BriefScaffold(
            padding: shellTabContentPadding(context),
            onRefresh: _refresh,
            greeting: const HealthGreetingHeader(),
            stage: stage,
            stickyBuilder: dataReady && hasRecovery
                ? (context, progress) =>
                      _HealthRecoveryStickyBar(progress: progress)
                : null,
            summaryTiles: dataReady
                ? staggeredSummaryTiles([
                    const AdaptiveSummaryTile(
                      role: AdaptiveSummaryTileRole.continuous,
                      child: HealthSourceAttention(),
                    ),
                    if (hasRecovery)
                      const AdaptiveSummaryTile(
                        role: AdaptiveSummaryTileRole.featured,
                        child: _MetricGrid(),
                      ),
                    if (!hasRecovery)
                      AdaptiveSummaryTile(
                        role: AdaptiveSummaryTileRole.continuous,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)
                                  .healthRecoveryBuilding,
                              style: context.labelStyle,
                            ),
                            const SizedBox(height: AppSpacing.s4),
                            Text(
                              AppLocalizations.of(context)
                                  .healthRecoveryBuildingHint,
                              style: context.captionStyle,
                            ),
                          ],
                        ),
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
                showChevron: false,
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
              if (ref
                      .watch(health_data.healthPlatformStatusProvider)
                      .value
                      ?.available ==
                  true) ...[
                SizedBox(
                  width: double.infinity,
                  child: FButton(
                    onPress: _running ? null : _activatePlatform,
                    child: _running
                        ? const FCircularProgress()
                        : Text(l10n.healthActivationAction),
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
              ],
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  FButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: _running ? null : _activateGarmin,
                    child: Text(l10n.healthActivationGarminAction),
                  ),
                  FButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: _running ? null : _recordManually,
                    child: Text(l10n.healthActivationManualAction),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
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
            child: HealthSourcesSummary(),
          ),
        ),
      ],
    );
  }
}

String _ago(AppLocalizations l10n, DateTime when) =>
    healthRelativeTime(l10n, when);
