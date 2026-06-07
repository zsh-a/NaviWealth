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
            _verdictHeadline(verdict),
            style: typography.xl.copyWith(
              color: _verdictColor(verdict, colors),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            _verdictSuggestion(verdict),
            style: typography.sm,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            '今日建议',
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s8),
          for (final item in _planActions(verdict))
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

  static String _verdictHeadline(String v) => switch (v) {
    'rested' => '充分恢复',
    'balanced' => '平衡',
    'strained' => '过载',
    _ => '数据不足',
  };

  static String _verdictSuggestion(String v) => switch (v) {
    'rested' => '身体信号支持更高负荷。',
    'balanced' => '维持节奏，不要把强度推到极限。',
    'strained' => '恢复信号偏弱，今天先保护睡眠和压力。',
    _ => '基线不足。继续连续记录 1-2 周后再看这里。',
  };

  static List<_PlanAction> _planActions(String v) => switch (v) {
    'rested' => const [
      _PlanAction(FLucideIcons.dumbbell, '可安排高强度训练或关键深度工作。'),
      _PlanAction(FLucideIcons.moon, '保持正常睡眠窗口，避免过度透支。'),
    ],
    'balanced' => const [
      _PlanAction(FLucideIcons.activity, '按原计划训练，保留 1-2 成余量。'),
      _PlanAction(FLucideIcons.coffee, '下午减少咖啡因，保持晚间恢复。'),
    ],
    'strained' => const [
      _PlanAction(FLucideIcons.footprints, '换成散步、拉伸或 Zone 2 轻量活动。'),
      _PlanAction(FLucideIcons.calendarX, '避免连续高压会议和晚间训练。'),
    ],
    _ => const [
      _PlanAction(FLucideIcons.refreshCw, '先同步 Health Connect 数据。'),
      _PlanAction(FLucideIcons.calendarDays, '连续记录几天后再判断趋势。'),
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
              '请在 设置 → Domains 中启用 HealthOS，才能查看恢复建议。',
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
        '不是医学诊断,仅供日常作息判断。HealthOS 不会自动调整你的日程。',
        style: context.captionStyle,
      ),
    );
  }
}
