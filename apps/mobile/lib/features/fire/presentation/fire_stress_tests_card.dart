import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ai_chat/ui/ai_hover_overlay.dart';
import '../data/fire_providers.dart';
import '../domain/fire_stress_test.dart';
import 'fire_ai_capsule.dart';
import 'fire_status_colors.dart';

/// Stress tests section — surfaces the deterministic resilience checks
/// (`runStressTests`) per `docs/roadmap-fire-os.md` §4.3. One row per
/// scenario with its parameters, verdict and the metrics that moved.
class FireStressTestsCard extends ConsumerWidget {
  const FireStressTestsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    final stressAsync = ref.watch(fireStressTestsProvider);
    return AiHoverOverlay(
      capsule: FireAiCapsule(
        intent: 'explain_stress_test',
        source: 'fire_stress_card',
        objectLabel: l10n.fireOsStressTitle,
      ),
      child: SoftCard(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.fireOsStressTitle, style: context.theme.typography.md),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.fireOsStressSubtitle,
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            stressAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
                child: SizedBox.shrink(),
              ),
              error: (e, _) => Text(
                '$e',
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.destructive,
                ),
              ),
              data: (results) {
                if (results.isEmpty) {
                  return Text(
                    l10n.fireOsStressEmpty,
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final r in results) ...[
                      _StressRow(result: r, formatters: formatters, l10n: l10n),
                      const SizedBox(height: AppSpacing.s10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StressRow extends StatelessWidget {
  const _StressRow({
    required this.result,
    required this.formatters,
    required this.l10n,
  });

  final FireStressResult result;
  final AppFormatters formatters;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final verdictColor = fireStressVerdictColor(SemanticColors.of(context), result.verdict);
    final scenarioLabel = _scenarioLabel(l10n, result, formatters);
    final verdictLabel = _verdictLabel(l10n, result.verdict);
    final wrLabel = result.withdrawalRateAfter.isFinite
        ? l10n.fireOsStressMetricWr(
            (result.withdrawalRateAfter * 100).toStringAsFixed(1),
          )
        : l10n.fireOsStressMetricWrInfinite;
    final cashLabel = result.cashBucketMonthsAfter.isFinite
        ? l10n.fireOsStressMetricCash(
            result.cashBucketMonthsAfter.toStringAsFixed(1),
          )
        : '—';
    final nwLabel = l10n.fireOsStressMetricNetWorth(
      formatters.currency(
        result.netWorthAfter.amount,
        code: result.netWorthAfter.currency,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                scenarioLabel,
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s2),
              decoration: BoxDecoration(
                color: verdictColor.withValues(alpha: AppOpacity.light),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: verdictColor.withValues(alpha: AppOpacity.disabled)),
              ),
              child: Text(
                verdictLabel,
                style: context.theme.typography.xs.copyWith(
                  color: verdictColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              wrLabel,
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            Text(
              cashLabel,
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            Text(
              nwLabel,
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _scenarioLabel(
  AppLocalizations l10n,
  FireStressResult r,
  AppFormatters formatters,
) {
  switch (r.scenario) {
    case FireStressScenario.marketDrawdown:
      return l10n.fireOsStressScenarioMarketDrawdown(
        ((r.params.drawdownPct ?? 0) * 100).toStringAsFixed(0),
      );
    case FireStressScenario.expenseSurge:
      return l10n.fireOsStressScenarioExpenseSurge(
        ((r.params.expenseShockPct ?? 0) * 100).toStringAsFixed(0),
      );
    case FireStressScenario.oneOffShock:
      final amount = r.params.amount ?? 0;
      final amountStr = formatters.currency(
        Decimal.parse(amount.toStringAsFixed(2)),
        code: r.netWorthAfter.currency,
      );
      return l10n.fireOsStressScenarioOneOffShock(amountStr);
    case FireStressScenario.fxShock:
      return l10n.fireOsStressScenarioFxShock(
        ((r.params.fxShockPct ?? 0) * 100).toStringAsFixed(0),
      );
    case FireStressScenario.cashDepletion:
      return l10n.fireOsStressScenarioCashDepletion(r.params.months ?? 0);
  }
}

String _verdictLabel(AppLocalizations l10n, FireStressVerdict v) {
  switch (v) {
    case FireStressVerdict.safe:
      return l10n.fireOsStressVerdictSafe;
    case FireStressVerdict.cautious:
      return l10n.fireOsStressVerdictCautious;
    case FireStressVerdict.danger:
      return l10n.fireOsStressVerdictDanger;
  }
}

