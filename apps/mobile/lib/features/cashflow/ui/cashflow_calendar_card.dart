import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/cash_flow_providers.dart';
import '../domain/cash_flow_aggregator.dart';
import '../domain/home_cash_flow_metrics.dart';

class CashflowCalendarCard extends ConsumerWidget {
  const CashflowCalendarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(
      cashFlowSummaryProvider(
        const CashFlowSummaryRequest(period: CashFlowPeriod.month),
      ),
    );
    return summary.when(
      loading: () => const _CashflowCalendarSkeleton(),
      error: (error, stackTrace) => const _CashflowCalendarError(),
      data: (value) => _CashflowCalendarContent(
        metrics: monthlyCashFlowHomeMetrics(
          value,
          now: ref.watch(cashFlowNowProvider),
        ),
      ),
    );
  }
}

class _CashflowCalendarContent extends ConsumerWidget {
  const _CashflowCalendarContent({required this.metrics});

  final MonthlyCashFlowHomeMetrics metrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final colors = context.theme.colors;
    final hasData = metrics.hasData;
    final positive = metrics.net.amount >= metrics.trailingAverageNet.amount;
    final accent = metrics.net.amount < Decimal.zero
        ? colors.destructive
        : positive
        ? Colors.teal
        : Colors.amber;

    return SoftCard(
      onPress: () => context.push(kCashflowPath),
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: SizedBox(
        height: 154,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: FLucideIcons.calendarDays,
              title: l10n.homeMonthlyCashFlowTitle,
              color: accent,
            ),
            const Spacer(),
            Text(
              hasData
                  ? formatters.currency(
                      metrics.net.amount,
                      code: metrics.net.currency,
                    )
                  : l10n.homeCashFlowEmptyValue,
              style: context.theme.typography.xl.copyWith(
                fontWeight: FontWeight.w700,
                color: metrics.net.amount < Decimal.zero
                    ? colors.destructive
                    : colors.foreground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              hasData
                  ? l10n.homeMonthlyCashFlowSubtitle(
                      formatters.compactCurrency(
                        metrics.inflow.amount,
                        code: metrics.inflow.currency,
                      ),
                      formatters.compactCurrency(
                        metrics.outflow.amount,
                        code: metrics.outflow.currency,
                      ),
                    )
                  : l10n.homeMonthlyCashFlowEmpty,
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.s12),
            _CashflowBalanceBar(
              ratio: hasData ? metrics.progressRatio : 0,
              color: accent,
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              hasData
                  ? l10n.homeMonthlyCashFlowBaseline(
                      formatters.compactCurrency(
                        metrics.trailingAverageNet.amount,
                        code: metrics.trailingAverageNet.currency,
                      ),
                    )
                  : l10n.homeMonthlyCashFlowBaselineEmpty,
              style: context.theme.typography.xs2.copyWith(
                color: colors.mutedForeground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CashflowCalendarSkeleton extends StatelessWidget {
  const _CashflowCalendarSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      padding: EdgeInsets.all(AppSpacing.s16),
      child: SizedBox(
        height: 154,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 148, height: 18, radius: 5),
            Spacer(),
            SkeletonBox(width: 128, height: 28, radius: 6),
            SizedBox(height: AppSpacing.s8),
            SkeletonBox(width: 182, height: 14, radius: 5),
            SizedBox(height: AppSpacing.s12),
            SkeletonBox(width: double.infinity, height: 12, radius: 6),
          ],
        ),
      ),
    );
  }
}

class _CashflowCalendarError extends StatelessWidget {
  const _CashflowCalendarError();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: SizedBox(
        height: 154,
        child: Text(
          AppLocalizations.of(context).homeCashFlowCardError,
          style: context.theme.typography.sm.copyWith(
            color: context.theme.colors.destructive,
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            title,
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(
          FLucideIcons.chevronRight,
          size: 18,
          color: context.theme.colors.mutedForeground.withValues(alpha: 0.6),
        ),
      ],
    );
  }
}

class _CashflowBalanceBar extends StatelessWidget {
  const _CashflowBalanceBar({required this.ratio, required this.color});

  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.s12,
      child: CustomPaint(
        painter: _CashflowBalancePainter(
          ratio: ratio,
          color: color,
          trackColor: context.theme.colors.muted,
          zeroColor: context.theme.colors.border,
        ),
      ),
    );
  }
}

class _CashflowBalancePainter extends CustomPainter {
  const _CashflowBalancePainter({
    required this.ratio,
    required this.color,
    required this.trackColor,
    required this.zeroColor,
  });

  final double ratio;
  final Color color;
  final Color trackColor;
  final Color zeroColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final trackRect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = trackColor,
    );

    final center = size.width / 2;
    final width = (size.width / 2) * ratio.abs().clamp(0, 1);
    final fillRect = ratio >= 0
        ? Rect.fromLTWH(center, 0, width, size.height)
        : Rect.fromLTWH(center - width, 0, width, size.height);
    if (width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, radius),
        Paint()..color = color,
      );
    }
    canvas.drawLine(
      Offset(center, 1),
      Offset(center, size.height - 1),
      Paint()
        ..color = zeroColor
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _CashflowBalancePainter oldDelegate) {
    return oldDelegate.ratio != ratio ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.zeroColor != zeroColor;
  }
}
