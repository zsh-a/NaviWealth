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
import 'health_today_providers.dart';

class HealthPlanPage extends ConsumerWidget {
  const HealthPlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recoverySignalProvider);
    return ShellTabScaffold(
      title: '计划 · HealthOS',
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
                '恢复',
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
          if (out['note'] is String) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              out['note'] as String,
              style: typography.xs.copyWith(color: colors.mutedForeground),
            ),
          ],
          const Divider(height: AppSpacing.s24),
          Text(
            '输入指标',
            style: typography.xs.copyWith(color: colors.mutedForeground),
          ),
          const SizedBox(height: AppSpacing.s8),
          _InputRow(
            label: 'HRV（近期均值）',
            value: _format(inputs['latest_hrv_ms'], unit: 'ms'),
          ),
          _InputRow(
            label: '睡眠（近期均值）',
            value: _format(inputs['avg_sleep_hours'], unit: 'h'),
          ),
          _InputRow(
            label: '静息心率（近期均值）',
            value: _format(inputs['latest_rhr_bpm'], unit: 'bpm'),
          ),
          _InputRow(
            label: 'VO₂max（近期均值）',
            value: _format(inputs['latest_vo2_max'], unit: 'ml/(kg·min)'),
          ),
        ],
      ),
    );
  }

  static IconData _verdictIcon(String v) => switch (v) {
    'rested' => Icons.bolt,
    'balanced' => Icons.balance,
    'strained' => Icons.warning_amber_outlined,
    _ => Icons.help_outline,
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
    'rested' => '今天可以推高强度训练 / 长会议日。HRV 与睡眠都好于基线。',
    'balanced' => '维持平时节奏即可,不建议推到极限。',
    'strained' => '建议减负:轻量训练、午睡、避免高压会议。HRV / RHR / 睡眠 至少一项明显偏离基线。',
    _ => '基线不足。继续连续记录 1-2 周后再看这里。',
  };

  static String _format(Object? v, {required String unit}) {
    if (v == null) return '—';
    return '$v $unit';
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: typography.xs.copyWith(color: colors.mutedForeground),
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
      child: SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
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
          Icon(Icons.info_outline, color: colors.mutedForeground),
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
          Icon(Icons.error_outline, color: colors.destructive),
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
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      child: Text(
        '不是医学诊断,仅供日常作息判断。HealthOS 不会自动调整你的日程。',
        style: typography.xs.copyWith(color: colors.mutedForeground),
      ),
    );
  }
}
