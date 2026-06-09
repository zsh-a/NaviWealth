/// HealthOS Plan surface (`docs/healthos-domain.md` §5, D-2.7).
///
/// MVP plan page = surface the existing `get_recovery_signal` shape
/// for humans. Verdict + score + inputs (HRV / sleep / RHR / VO₂max)
/// + one suggestion line keyed off the verdict. No autonomous schedule
/// modification — §10 反目标.
///
/// Chrome matches the rest of LifeOS (`docs/lifeos-shell.md` §3):
/// `FScaffold` + `FHeader.nested`, `SoftCard` surfaces and
/// `context.theme` tokens rather than Material `Scaffold` / `Theme.of`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
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
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: [
          async.when(
            loading: () => const _LoadingCard(),
            error: (e, _) => _ErrorCard(message: '$e'),
            data: (out) =>
                out == null ? const _OffCard() : _RecoveryCard(out: out),
          ),
          const SizedBox(height: AppSpacing.s12),
          const _DisclaimerCard(),
        ],
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({required this.out});
  final Map<String, Object?> out;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final verdict = out['verdict']?.toString() ?? 'insufficient_data';
    final score = out['score'];
    final inputs = (out['inputs'] as Map?)?.cast<String, Object?>() ?? const {};
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _verdictIcon(verdict),
                color: _verdictColor(verdict, colors),
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                l10n.healthTrendGroupRecovery,
                style: typography.sm.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (score != null)
                Text(
                  '$score',
                  style: typography.xl.copyWith(
                    color: _verdictColor(verdict, colors),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            _verdictHeadline(verdict, l10n),
            style: typography.xl.copyWith(
              color: _verdictColor(verdict, colors),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            _verdictSuggestion(verdict, l10n, inputs: inputs),
            style: typography.sm,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.healthPlanTodayActions,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s8),
          for (final item in _planActions(verdict, l10n))
            _PlanActionRow(icon: item.icon, text: item.text),
          if (out['note'] is String) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              out['note'] as String,
              style: context.captionStyle,
            ),
          ],
          const SizedBox(height: AppSpacing.s24),
          Text(
            l10n.healthInputMetricsTitle,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s8),
          _InputRow(
            label: l10n.healthConfidenceLabel,
            value: score == null
                ? l10n.healthConfidenceLow
                : l10n.healthConfidenceMedium,
          ),
          _InputRow(
            label: l10n.healthRecentHrvLabel,
            value: _format(inputs['latest_hrv_ms'], unit: 'ms'),
          ),
          _InputRow(
            label: l10n.healthRecentSleepLabel,
            value: _format(inputs['avg_sleep_hours'], unit: 'h'),
          ),
          _InputRow(
            label: l10n.healthRecentRhrLabel,
            value: _format(inputs['latest_rhr_bpm'], unit: 'bpm'),
          ),
          _InputRow(
            label: l10n.healthRecentVo2MaxLabel,
            value: _format(inputs['latest_vo2_max'], unit: 'ml/(kg·min)'),
          ),
        ],
      ),
    );
  }

  static IconData _verdictIcon(String v) => switch (v) {
    'rested' => FLucideIcons.zap,
    'balanced' => FLucideIcons.scale,
    'strained' => FLucideIcons.triangleAlert,
    _ => FLucideIcons.circleHelp,
  };

  static Color _verdictColor(String v, FColors colors) => switch (v) {
    'rested' => colors.primary,
    'balanced' => colors.mutedForeground,
    'strained' => colors.destructive,
    _ => colors.mutedForeground,
  };

  static String _verdictHeadline(String v, AppLocalizations l10n) => switch (v) {
    'rested' => l10n.healthRecoveryRested,
    'balanced' => l10n.healthRecoveryBalanced,
    'strained' => l10n.healthRecoveryStrained,
    _ => l10n.healthRecoveryInsufficient,
  };

  static String _verdictSuggestion(
    String v,
    AppLocalizations l10n, {
    Map<String, Object?> inputs = const {},
  }) {
    // Build a data-aware context line when inputs are available.
    final hrv = inputs['latest_hrv_ms'];
    final sleep = inputs['avg_sleep_hours'];
    final rhr = inputs['latest_rhr_bpm'];

    final contextLine = _buildContextLine(
      hrv: hrv,
      sleep: sleep,
      rhr: rhr,
    );

    final base = switch (v) {
      'rested' => l10n.healthRecoveryRestedTip,
      'balanced' => l10n.healthRecoveryBalancedTip,
      'strained' => l10n.healthRecoveryStrainedTip,
      _ => l10n.healthRecoveryInsufficientTip,
    };

    if (contextLine.isEmpty) return base;
    return '$contextLine $base';
  }

  /// Build a one-line data context summary when metric values are available.
  static String _buildContextLine({
    Object? hrv,
    Object? sleep,
    Object? rhr,
  }) {
    final parts = <String>[];
    if (hrv is num && hrv > 0) {
      parts.add('HRV ${_round(hrv.toDouble())} ms');
    }
    if (sleep is num && sleep > 0) {
      parts.add('sleep ${_round(sleep.toDouble())}h');
    }
    if (rhr is num && rhr > 0) {
      parts.add('RHR ${_round(rhr.toDouble())} bpm');
    }
    if (parts.isEmpty) return '';
    return '${parts.join(' · ')}.';
  }

  static double _round(double v) => (v * 100).round() / 100.0;

  static List<_PlanAction> _planActions(String v, AppLocalizations l10n) => switch (v) {
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

  static String _format(Object? v, {required String unit}) {
    if (v == null) return '—';
    return '$v $unit';
  }
}

class _PlanAction {
  const _PlanAction(this.icon, this.text);
  final IconData icon;
  final String text;
}

class _PlanActionRow extends StatelessWidget {
  const _PlanActionRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppIconSizes.sm, color: colors.mutedForeground),
          const SizedBox(width: AppSpacing.s8),
          Expanded(child: Text(text, style: typography.sm)),
        ],
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.captionStyle,
            ),
          ),
          Text(value, style: typography.sm),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      padding: EdgeInsets.all(AppSpacing.s16),
      child: SizedBox(height: 80, child: Center(child: FCircularProgress())),
    );
  }
}

class _OffCard extends StatelessWidget {
  const _OffCard();
  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        children: [
          Icon(FLucideIcons.info, color: colors.mutedForeground),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              l10n.healthPlanEnableHint,
              style: typography.sm,
            ),
          ),
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
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        children: [
          Icon(FLucideIcons.circleAlert, color: colors.destructive),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              'Plan 加载失败：$message',
              style: typography.sm,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      child: Text(
        AppLocalizations.of(context).healthPlanDisclaimer,
        style: context.captionStyle,
      ),
    );
  }
}
