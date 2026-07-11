/// HealthOS Plan surface (`docs/domains/healthos-domain.md` §5, D-2.7).
///
/// Plan page = surface the existing `get_recovery_signal` shape for humans
/// as concrete same-day training/recovery actions. Verdict + score + inputs
/// (HRV / sleep / RHR / VO₂max) drive multiple suggestion rows keyed off the
/// verdict. No autonomous schedule modification — §10 反目标.
///
/// Chrome matches the rest of LifeOS (`docs/architecture/lifeos-shell.md` §3):
/// `FScaffold` + `FHeader.nested`, `SoftCard` surfaces and
/// `context.theme` tokens rather than Material `Scaffold` / `Theme.of`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'health_metric_colors.dart';
import 'health_today_providers.dart';

class HealthPlanPage extends ConsumerWidget {
  const HealthPlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(recoverySignalProvider);
    return ShellTabScaffold(
      title: l10n.healthPlanTitle,
      child: ListView(
        padding: shellTabContentPadding(context),
        children: [
          FadeSlideIn(
            child: async.when(
              loading: () => const _LoadingCard(),
              error: (e, _) =>
                  _ErrorCard(message: userSafeErrorMessage(context, e)),
              data: (out) {
                if (out == null) return const _OffCard();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ActionPlanCard(out: out),
                    const SizedBox(height: AppSpacing.s16),
                    _InputMetricsCard(out: out),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          const FadeSlideIn(child: _DisclaimerCard()),
        ],
      ),
    );
  }
}

/// Action plan card with icon disc rows.
class _ActionPlanCard extends StatelessWidget {
  const _ActionPlanCard({required this.out});
  final Map<String, Object?> out;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final verdict = out['verdict']?.toString() ?? 'insufficient_data';
    final actions = _planActions(verdict, l10n);
    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.listChecks,
                size: AppIconSizes.h18,
                color: colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(l10n.healthPlanTodayActions, style: context.mutedLabelStyle),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          for (final action in actions) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIconTile(
                  icon: action.icon,
                  color: colors.primary,
                  size: 28,
                  iconSize: AppIconSizes.sm,
                  radius: AppRadius.xs,
                  backgroundOpacity: AppOpacity.light,
                  foregroundOpacity: 1,
                ),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s4),
                    child: Text(
                      action.text,
                      style: typography.body.sm,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            if (action != actions.last) const SizedBox(height: AppSpacing.s10),
          ],
          if (out['note'] is String) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              out['note'] as String,
              style: context.captionStyle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  static List<_PlanAction> _planActions(String v, AppLocalizations l10n) =>
      switch (v) {
        'rested' => [
          _PlanAction(FLucideIcons.dumbbell, l10n.healthPlanHighIntensity),
          _PlanAction(FLucideIcons.moon, l10n.healthPlanKeepSleep),
        ],
        'balanced' => [
          _PlanAction(FLucideIcons.activity, l10n.healthPlanTrainAsPlanned),
          _PlanAction(FLucideIcons.coffee, l10n.healthPlanReduceCaffeine),
        ],
        'strained' => [
          _PlanAction(FLucideIcons.footprints, l10n.healthPlanLightActivity),
          _PlanAction(FLucideIcons.calendarX, l10n.healthPlanAvoidPressure),
        ],
        _ => [
          _PlanAction(FLucideIcons.refreshCw, l10n.healthPlanSyncFirst),
          _PlanAction(FLucideIcons.calendarDays, l10n.healthPlanTrackMore),
        ],
      };
}

/// Input metrics displayed in a 2-column grid.
class _InputMetricsCard extends StatefulWidget {
  const _InputMetricsCard({required this.out});
  final Map<String, Object?> out;

  @override
  State<_InputMetricsCard> createState() => _InputMetricsCardState();
}

class _InputMetricsCardState extends State<_InputMetricsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final out = widget.out;
    final score = out['score'];
    final inputs = (out['inputs'] as Map?)?.cast<String, Object?>() ?? const {};
    final metrics = <_MetricItem>[
      _MetricItem(
        icon: FLucideIcons.gauge,
        label: l10n.healthConfidenceLabel,
        value: score == null
            ? l10n.healthConfidenceLow
            : l10n.healthConfidenceMedium,
        color: HealthMetricColors.confidence,
      ),
      _MetricItem(
        icon: FLucideIcons.heartPulse,
        label: l10n.healthRecentHrvLabel,
        value: _format(inputs['latest_hrv_ms'], unit: 'ms'),
        color: HealthMetricColors.hrv,
      ),
      _MetricItem(
        icon: FLucideIcons.moon,
        label: l10n.healthRecentSleepLabel,
        value: _format(inputs['avg_sleep_hours'], unit: 'h'),
        color: HealthMetricColors.sleep,
      ),
      _MetricItem(
        icon: FLucideIcons.heart,
        label: l10n.healthRecentRhrLabel,
        value: _format(inputs['latest_rhr_bpm'], unit: 'bpm'),
        color: HealthMetricColors.rhr,
      ),
      _MetricItem(
        icon: FLucideIcons.activity,
        label: l10n.healthRecentVo2MaxLabel,
        value: _format(inputs['latest_vo2_max'], unit: 'ml/(kg·min)'),
        color: HealthMetricColors.vo2Max,
      ),
    ];
    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FTappable(
            onPress: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(
                  FLucideIcons.chartColumn,
                  size: AppIconSizes.h18,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    l10n.healthInputMetricsTitle,
                    style: context.mutedLabelStyle,
                  ),
                ),
                Icon(
                  _expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                for (final m in metrics)
                  AppInfoChip(
                    icon: m.icon,
                    value: m.value,
                    label: m.label,
                    color: m.color,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _format(Object? v, {required String unit}) {
    if (v == null) return '—';
    return '$v $unit';
  }
}

class _MetricItem {
  const _MetricItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

class _PlanAction {
  const _PlanAction(this.icon, this.text);
  final IconData icon;
  final String text;
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      padding: EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 40, height: 40, radius: AppRadius.sm),
              SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 60, height: 10),
                    SizedBox(height: AppSpacing.s4),
                    SkeletonBox(width: 100, height: 18),
                  ],
                ),
              ),
              SkeletonBox(width: 32, height: 24),
            ],
          ),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(width: 200, height: 14),
        ],
      ),
    );
  }
}

class _OffCard extends StatelessWidget {
  const _OffCard();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppStatusBanner(
      kind: AppStatusKind.info,
      message: l10n.healthPlanEnableHint,
      icon: FLucideIcons.info,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppStatusBanner(
      kind: AppStatusKind.error,
      message: l10n.healthPlanLoadFailed(message),
      icon: FLucideIcons.circleAlert,
    );
  }
}

class _DisclaimerCard extends StatefulWidget {
  const _DisclaimerCard();

  @override
  State<_DisclaimerCard> createState() => _DisclaimerCardState();
}

class _DisclaimerCardState extends State<_DisclaimerCard> {
  bool _expanded = false;
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.info,
                size: AppIconSizes.h18,
                color: colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  l10n.healthPlanDisclaimerTitle,
                  style: context.captionLabelStyle,
                ),
              ),
              FButton(
                variant: FButtonVariant.ghost,
                onPress: () => setState(() => _expanded = !_expanded),
                child: Icon(
                  _expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                  size: AppIconSizes.h18,
                ),
              ),
              FButton(
                variant: FButtonVariant.ghost,
                onPress: () => setState(() => _dismissed = true),
                child: const Icon(FLucideIcons.x, size: AppIconSizes.h18),
              ),
            ],
          ),
          AnimatedCrossFade(
            firstChild: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.s8,
                left: AppSpacing.s28,
              ),
              child: Text(
                l10n.healthPlanDisclaimer,
                style: context.captionStyle,
              ),
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: AppMotionPolicy.duration(context, Motion.fast),
          ),
        ],
      ),
    );
  }
}
