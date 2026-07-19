/// HealthOS Today surface (`docs/domains/healthos-domain.md` §8, D-2.5b
/// follow-up).
///
/// Renders HealthKit/Garmin sync status, recovery, key metrics, weekly
/// summary, and the latest Morning Briefing. Trend and Plan now have MVP
/// surfaces; Today stays the dense operational entry point.
///
/// Chrome matches the rest of LifeOS (`docs/architecture/lifeos-shell.md` §3): the
/// ForUI `FScaffold` + `FHeader.nested` shell, `SoftCard` surfaces and
/// `context.theme` tokens — never Material `Scaffold` / `Theme.of` —
/// so HealthOS reads as the same app as Finance / Knowledge.
library;

import 'dart:async' show FutureOr;
import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_access.dart';
import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/ui/agent_result_card.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/format/formatters.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as health_agent_providers;
import '../agents/recovery_alert_agent.dart' show kRecoveryAlertAgentId;
import '../agents/weekly_summary_agent.dart' show kWeeklySummaryAgentId;
import '../composition/health_route_paths.dart';
import '../data/health_metric_source.dart';
import '../data/health_sync_service.dart';
import '../data/providers.dart' as health_data;
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'body_measurement_entry_sheet.dart';
import 'garmin_sync_status_card.dart';
import 'health_metric_colors.dart';
import 'health_today_providers.dart';
import 'health_trend_page.dart' show healthTrendPath;
import 'plan_actions.dart';
import 'recovery_verdict.dart';

part 'briefing_panel.dart';
part 'metric_grid.dart';
part 'metric_grid_cards.dart';
part 'metric_grid_primitives.dart';
part 'recovery_hero.dart';
part 'weekly_summary_panel.dart';

class HealthTodayPage extends ConsumerStatefulWidget {
  const HealthTodayPage({super.key, this.initialAgentArtifactId});

  final String? initialAgentArtifactId;

  @override
  ConsumerState<HealthTodayPage> createState() => _HealthTodayPageState();
}

class _HealthTodayPageState extends ConsumerState<HealthTodayPage> {
  String? _openedInitialArtifactId;

  @override
  Widget build(BuildContext context) {
    _maybeOpenInitialArtifactSheet();
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.healthTodayTitle,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.scale,
          label: l10n.healthRecordBodyMetricAction,
          onPress: () async {
            final saved = await showBodyMeasurementEntrySheet(
              context: context,
              initialKind: HealthMetricKind.weight,
            );
            if (saved == true) ref.invalidate(healthTodaySnapshotProvider);
          },
        ),
      ],
      child: ShellTabPause(
        routePath: HealthRoutes.today,
        child: BriefScaffold(
          padding: shellTabContentPadding(context),
          onRefresh: () async {
            ref.invalidate(healthTodaySnapshotProvider);
            ref.invalidate(health_agent_providers.latestMorningBriefingProvider);
            ref.invalidate(
              health_agent_providers.latestMorningBriefingArtifactProvider,
            );
            ref.invalidate(
              health_agent_providers.latestRecoveryAlertArtifactProvider,
            );
            ref.invalidate(
              health_agent_providers.latestRecoveryAlertRunProvider,
            );
            ref.invalidate(
              health_agent_providers.latestHealthReviewAgentResultsProvider,
            );
            await ref.read(healthTodaySnapshotProvider.future);
          },
          greeting: const SizedBox.shrink(),
          // Hero = recovery verdict + same-day actions (ex-Plan).
          stage: const FadeSlideIn(child: _RecoveryHero()),
          stickyBuilder: (context, progress) =>
              _HealthRecoveryStickyBar(progress: progress),
          modules: const [
            // Signal first: alerts only when real; briefing promoted.
            _RecoveryAlertPanel(),
            _BriefingPanel(),
            _MetricGrid(),
          ],
          secondary: const [_SourcesSection(), _WeeklySummaryPanel()],
        ),
      ),
    );
  }

  void _maybeOpenInitialArtifactSheet() {
    final artifactId = widget.initialAgentArtifactId;
    if (artifactId == null ||
        artifactId.isEmpty ||
        _openedInitialArtifactId == artifactId) {
      return;
    }
    _openedInitialArtifactId = artifactId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final artifact = await readActiveAgentArtifactFromWidgetRef(
        ref,
        artifactId: artifactId,
        expectedDomain: DomainScope.health.wire,
      );
      if (!mounted || artifact == null) return;
      final l10n = AppLocalizations.of(context);
      final metaLabel = l10n.healthBriefingUpdated(
        _ago(l10n, artifact.createdAt),
      );
      await showAgentArtifactSheet(
        context: context,
        artifact: artifact,
        subtitle: metaLabel,
        onVisibilityChanged: () {
          ref.invalidate(
            health_agent_providers.latestMorningBriefingArtifactProvider,
          );
          ref.invalidate(
            health_agent_providers.latestRecoveryAlertArtifactProvider,
          );
          ref.invalidate(health_agent_providers.latestRecoveryAlertRunProvider);
          ref.invalidate(
            health_agent_providers.latestHealthReviewAgentResultsProvider,
          );
        },
      );
    });
  }
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
      child: Row(
        children: [
          AppIconTile(
            icon: RecoveryVerdict.icon(verdict),
            color: accent,
            size: 28,
            iconSize: AppIconSizes.sm,
            radius: AppRadius.sm,
            backgroundOpacity: AppOpacity.subtle,
            foregroundOpacity: 1,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Text(
              RecoveryVerdict.label(verdict, l10n),
              style: context.labelStyle.copyWith(color: accent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (scoreText != null)
            Text(
              scoreText,
              style: TypographyTokens.numericTitleStrong.copyWith(
                color: accent,
              ),
            ),
        ],
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
        if (constraints.maxWidth < 720) {
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
          return;
        }
      }
      final result = await service.syncRange();
      if (!mounted) return;
      setState(() => _lastResult = result);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactAction = constraints.maxWidth < 360;
        return SoftCard(
          level: SoftCardLevel.raised,
          borderless: true,
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
                      _healthKitText(l10n, enabled),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
                      const SizedBox(width: AppSpacing.s6),
                      Text(l10n.healthSyncAction),
                    ],
                  ),
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
    if (result == null) return colors.mutedForeground;
    return result.ok ? colors.primary : colors.destructive;
  }

  String _healthKitText(AppLocalizations l10n, bool enabled) {
    if (!enabled) return l10n.healthNotEnabled;
    if (_syncing) return l10n.healthSyncingData;
    final result = _lastResult;
    if (result == null) return l10n.healthSyncReady;
    if (result.ok) {
      return l10n.healthSyncResult('${result.unchanged}', '${result.upserted}');
    }
    return result.errorMessage ?? l10n.healthSyncFailed;
  }
}

class _HealthPanelHeader extends StatelessWidget {
  const _HealthPanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIconTile(
          icon: icon,
          color: color,
          size: 36,
          iconSize: AppIconSizes.h18,
          backgroundOpacity: AppOpacity.medium,
          foregroundOpacity: 1,
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.labelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                subtitle,
                style: context.captionStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.s8),
          trailing!,
        ],
      ],
    );
  }
}
