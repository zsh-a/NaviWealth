import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/cash_flow_providers.dart';
import '../data/dividend_forecast_providers.dart';
import '../domain/cash_flow_aggregator.dart';
import '../domain/home_cash_flow_metrics.dart';

class PassiveIncomeCard extends ConsumerWidget {
  const PassiveIncomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(
      cashFlowSummaryProvider(
        const CashFlowSummaryRequest(period: CashFlowPeriod.month),
      ),
    );
    return summary.when(
      loading: () => const _PassiveIncomeSkeleton(),
      error: (error, stackTrace) => _PassiveIncomeError(error: error),
      data: (value) => _PassiveIncomeContent(
        metrics: passiveIncomeHomeMetrics(
          value,
          now: ref.watch(cashFlowNowProvider),
        ),
      ),
    );
  }
}

class _PassiveIncomeContent extends ConsumerWidget {
  const _PassiveIncomeContent({required this.metrics});

  final PassiveIncomeHomeMetrics metrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final colors = context.theme.colors;
    final forecast = ref.watch(dividendForecast12mProvider);
    final projection = forecast.hasValue ? forecast.value : null;
    final nextMonthAmount =
        projection?.amountInMonth(
          _nextMonthStart(ref.watch(cashFlowNowProvider)),
        ) ??
        Decimal.zero;
    final hasData = metrics.hasData;
    final changeRatio = metrics.changeRatio;
    final trendColor = changeRatio == null
        ? colors.mutedForeground
        : changeRatio >= 0
        ? AccentColors.series
        : colors.destructive;

    return SoftCard(
      onPress: () => context.push(AppRoutes.cashflowDividends),
      padding: const EdgeInsets.all(AppSpacing.s16),
      borderRadius: AppRadius.xlg,
      borderless: true,
      level: SoftCardLevel.raised,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppMetricHeader(
              icon: FLucideIcons.piggyBank,
              title: l10n.homePassiveIncomeTitle,
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              hasData
                  ? formatters.compactCurrency(
                      metrics.totalTtm.amount,
                      code: metrics.totalTtm.currency,
                    )
                  : l10n.homeCashFlowEmptyValue,
              style: context.strongHeadlineStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              hasData
                  ? nextMonthAmount > Decimal.zero && projection != null
                        ? l10n.homePassiveIncomeSubtitleWithNextMonth(
                            formatters.compactCurrency(
                              nextMonthAmount,
                              code: projection.currency,
                            ),
                          )
                        : l10n.homePassiveIncomeSubtitle
                  : l10n.homePassiveIncomeEmpty,
              style: context.captionStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: AppChartHeights.sparkline,
                    child: _PassiveIncomeSparkline(
                      values: metrics.monthlyTotals
                          .map((money) => money.amount)
                          .toList(growable: false),
                      color: hasData ? trendColor : colors.mutedForeground,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                AppBadge(
                  label: changeRatio == null
                      ? l10n.homePassiveIncomeDeltaNew
                      : formatters.signedPercent(changeRatio, decimalDigits: 1),
                  foregroundColor: trendColor,
                  containerColor: trendColor.withValues(
                    alpha: AppOpacity.light,
                  ),
                  minWidth: 58,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

DateTime _nextMonthStart(DateTime now) {
  final utc = now.toUtc();
  final monthIndex = utc.year * 12 + utc.month;
  return DateTime.utc(monthIndex ~/ 12, monthIndex % 12 + 1);
}

class _PassiveIncomeSkeleton extends StatelessWidget {
  const _PassiveIncomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      padding: EdgeInsets.all(AppSpacing.s16),
      borderRadius: AppRadius.xlg,
      borderless: true,
      level: SoftCardLevel.raised,
      child: SizedBox(
        height: AppChartHeights.compact,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 132, height: 18, radius: 5),
            Spacer(),
            SkeletonBox(width: 116, height: 28, radius: 6),
            SizedBox(height: AppSpacing.s8),
            SkeletonBox(width: 180, height: 14, radius: 5),
            SizedBox(height: AppSpacing.s12),
            SkeletonBox(width: double.infinity, height: 34, radius: 8),
          ],
        ),
      ),
    );
  }
}

class _PassiveIncomeError extends StatelessWidget {
  const _PassiveIncomeError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      borderRadius: AppRadius.xlg,
      borderless: true,
      level: SoftCardLevel.raised,
      child: SizedBox(
        height: AppChartHeights.compact,
        child: Text(
          AppLocalizations.of(context).homeCashFlowCardError,
          style: context.theme.typography.body.sm.copyWith(
            color: colors.destructive,
          ),
        ),
      ),
    );
  }
}

class _PassiveIncomeSparkline extends StatelessWidget {
  const _PassiveIncomeSparkline({required this.values, required this.color});

  final List<Decimal> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(
        values: values.map((value) => value.toDouble()).toList(growable: false),
        color: color,
        guideColor: context.theme.colors.border.withValues(
          alpha: AppOpacity.scrim,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.color,
    required this.guideColor,
  });

  final List<double> values;
  final Color color;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = guideColor
      ..strokeWidth = AppStroke.hairline;
    canvas.drawLine(
      Offset(0, size.height * 0.72),
      Offset(size.width, size.height * 0.72),
      guidePaint,
    );

    if (values.length < 2 || values.every((value) => value == 0)) {
      return;
    }
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue - minValue;
    final step = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final ratio = range == 0 ? 0.5 : (values[i] - minValue) / range;
      final point = Offset(
        i * step,
        size.height - (ratio * size.height).clamp(3, size.height - 3),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = AppStroke.sparkline,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.guideColor != guideColor;
  }
}
