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

import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/ui/agent_result_card.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/format/formatters.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as health_agent_providers;
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
import 'recovery_verdict.dart';

part 'briefing_panel.dart';
part 'metric_grid.dart';
part 'metric_grid_cards.dart';
part 'metric_grid_primitives.dart';
part 'recovery_hero.dart';
part 'weekly_summary_panel.dart';

class HealthTodayPage extends ConsumerWidget {
  const HealthTodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.healthTodayTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.scale),
          semanticsLabel: l10n.healthRecordBodyMetricAction,
          onPress: () async {
            final saved = await showBodyMeasurementEntrySheet(
              context: context,
              initialKind: HealthMetricKind.weight,
            );
            if (saved == true) ref.invalidate(healthTodaySnapshotProvider);
          },
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(healthTodaySnapshotProvider);
          ref.invalidate(health_agent_providers.latestMorningBriefingProvider);
          ref.invalidate(
            health_agent_providers.latestMorningBriefingArtifactProvider,
          );
          await ref.read(healthTodaySnapshotProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: shellTabContentPadding(context),
          children: const [
            FadeSlideIn(child: _DataSourcePanel()),
            SizedBox(height: AppSpacing.s16),
            FadeSlideIn(child: _RecoveryHero()),
            SizedBox(height: AppSpacing.s16),
            FadeSlideIn(child: _MetricGrid()),
            SizedBox(height: AppSpacing.s16),
            FadeSlideIn(child: _WeeklySummaryPanel()),
            SizedBox(height: AppSpacing.s16),
            FadeSlideIn(child: _BriefingPanel()),
          ],
        ),
      ),
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
          if (_syncing)
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

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Row(
          children: [
            Icon(icon, size: AppIconSizes.h18, color: colors.mutedForeground),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                message,
                style: context.captionStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
