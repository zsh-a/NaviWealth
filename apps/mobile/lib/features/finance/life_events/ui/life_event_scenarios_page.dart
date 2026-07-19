import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../core/ai/composition/ask_ai.dart';
import '../../../../core/format/providers.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/financial_decision_providers.dart';
import '../domain/financial_decision.dart';
import '../domain/life_event_scenario.dart';

class LifeEventScenariosPage extends ConsumerWidget {
  const LifeEventScenariosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final baseline = ref.watch(lifeEventBaselineProvider);
    final decisions = ref.watch(financialDecisionsProvider);
    return AppPageScaffold(
      title: l10n.lifeEventScenariosTitle,
      childPad: false,
      child: baseline == null
          ? AppEmptyState(
              icon: FLucideIcons.waypoints,
              title: l10n.lifeEventScenariosEmptyTitle,
              message: l10n.lifeEventScenariosEmptyBody,
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.s16,
                AppSpacing.s12,
                AppSpacing.s16,
                AppSpacing.s32 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Text(
                  l10n.lifeEventScenariosIntro,
                  style: context.bodyCaptionStyle,
                ),
                const SizedBox(height: AppSpacing.s16),
                for (final template in LifeEventTemplate.values) ...[
                  _ScenarioCard(template: template, baseline: baseline),
                  const SizedBox(height: AppSpacing.s12),
                ],
                if (decisions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    l10n.lifeEventDecisionHistory,
                    style: context.mutedLabelStyle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  for (final decision in decisions)
                    _DecisionRow(decision: decision, baseline: baseline),
                ],
              ],
            ),
    );
  }
}

class _ScenarioCard extends ConsumerWidget {
  const _ScenarioCard({required this.template, required this.baseline});

  final LifeEventTemplate template;
  final LifeEventBaseline baseline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatter = context.formatters(ref);
    const engine = LifeEventScenarioEngine();
    final assumptions = engine.preset(template, baseline);
    final outcome = engine.simulate(baseline, assumptions);
    return SoftCard.raised(
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_templateLabel(l10n, template), style: context.rowTitleStyle),
          const SizedBox(height: AppSpacing.s6),
          Text(
            _assumptionCopy(l10n, template, assumptions.durationMonths),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          _MetricRow(
            label: l10n.lifeEventAfter90Days,
            value: formatter.currency(
              outcome.liquidAfter90Days,
              code: baseline.currency,
            ),
          ),
          _MetricRow(
            label: l10n.lifeEventAfter12Months,
            value: formatter.currency(
              outcome.liquidAfter12Months,
              code: baseline.currency,
            ),
          ),
          _MetricRow(
            label: l10n.lifeEventMonthlySurplus,
            value: formatter.currency(
              outcome.monthlySurplus,
              code: baseline.currency,
            ),
          ),
          if (outcome.estimatedFireDelayMonths != null)
            _MetricRow(
              label: l10n.lifeEventFireImpact,
              value: l10n.lifeEventFireDelay(outcome.estimatedFireDelayMonths!),
            ),
          const SizedBox(height: AppSpacing.s10),
          Row(
            children: [
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => askAi(
                    context,
                    ref,
                    intent: 'explain_financial_life_event',
                    objectLabel: _templateLabel(l10n, template),
                    attrs: {
                      'template': template.name,
                      'assumptions': assumptions.toJson(),
                      'deterministic_outcome': outcome.toJson(),
                      'instruction':
                          'Explain only from these deterministic results and ask about missing assumptions.',
                    },
                  ),
                  child: Text(l10n.lifeEventAskAi),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: FButton(
                  onPress: () async {
                    await ref
                        .read(productMetricsProvider.notifier)
                        .record(ProductFunnelEvent.lifeEventCompared);
                    await ref
                        .read(financialDecisionsProvider.notifier)
                        .save(
                          template: template,
                          assumptions: assumptions,
                          outcome: outcome,
                          now: DateTime.now(),
                        );
                    await ref
                        .read(productMetricsProvider.notifier)
                        .record(ProductFunnelEvent.financialDecisionSaved);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.lifeEventDecisionSaved)),
                      );
                    }
                  },
                  child: Text(l10n.lifeEventChooseScenario),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DecisionRow extends ConsumerWidget {
  const _DecisionRow({required this.decision, required this.baseline});

  final FinancialDecision decision;
  final LifeEventBaseline baseline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatter = context.formatters(ref);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: SoftCard.flat(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _templateLabel(l10n, decision.template),
                    style: context.labelStyle,
                  ),
                ),
                AppBadge(
                  label: decision.actualOutcome == null
                      ? l10n.lifeEventPendingReview
                      : l10n.lifeEventReviewed,
                  size: AppBadgeSize.compact,
                  tone: decision.actualOutcome == null
                      ? AppBadgeTone.warning
                      : AppBadgeTone.success,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              l10n.lifeEventReviewOn(
                formatter.date(decision.reviewDate.toLocal()),
              ),
              style: context.captionStyle,
            ),
            if (decision.actualOutcome != null) ...[
              const SizedBox(height: AppSpacing.s6),
              Text(
                l10n.lifeEventObservedDifference(
                  formatter.currency(
                    decision.actualOutcome!.liquidAfter90Days -
                        decision.selectedOutcome.liquidAfter90Days,
                    code: baseline.currency,
                  ),
                ),
                style: context.captionStyle,
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.s8),
              FButton(
                variant: FButtonVariant.ghost,
                onPress: () {
                  final actual = const LifeEventScenarioEngine().observe(
                    baseline,
                  );
                  ref
                      .read(financialDecisionsProvider.notifier)
                      .review(
                        id: decision.id,
                        actualOutcome: actual,
                        now: DateTime.now(),
                      );
                  ref
                      .read(productMetricsProvider.notifier)
                      .record(ProductFunnelEvent.financialDecisionReviewed);
                },
                child: Text(l10n.lifeEventCaptureActual),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: context.captionStyle)),
        Text(value, style: TypographyTokens.numericBodyStrong),
      ],
    ),
  );
}

String _templateLabel(AppLocalizations l10n, LifeEventTemplate template) =>
    switch (template) {
      LifeEventTemplate.largePurchase => l10n.lifeEventLargePurchase,
      LifeEventTemplate.careerBreak => l10n.lifeEventCareerBreak,
      LifeEventTemplate.homePurchase => l10n.lifeEventHomePurchase,
    };

String _assumptionCopy(
  AppLocalizations l10n,
  LifeEventTemplate template,
  int months,
) => switch (template) {
  LifeEventTemplate.largePurchase => l10n.lifeEventLargePurchaseAssumption,
  LifeEventTemplate.careerBreak => l10n.lifeEventCareerBreakAssumption(months),
  LifeEventTemplate.homePurchase => l10n.lifeEventHomePurchaseAssumption,
};
