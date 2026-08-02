import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/composition/ask_ai.dart';
import '../../../../core/format/providers.dart';
import '../../../../core/lifeos/action_dispatcher.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../composition/finance_route_paths.dart';
import '../../fire/data/fire_providers.dart';
import '../../fire/domain/fire_projection.dart';
import '../../runway/data/money_runway_providers.dart';
import '../data/financial_decision_providers.dart';
import '../domain/financial_decision.dart';
import '../domain/life_event_scenario.dart';

class LifeEventScenariosPage extends ConsumerStatefulWidget {
  const LifeEventScenariosPage({super.key});

  @override
  ConsumerState<LifeEventScenariosPage> createState() =>
      _LifeEventScenariosPageState();
}

class _LifeEventScenariosPageState
    extends ConsumerState<LifeEventScenariosPage> {
  LifeEventTemplate _selectedTemplate = LifeEventTemplate.largePurchase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final baseline = ref.watch(lifeEventBaselineProvider);
    final decisions =
        ref.watch(financialDecisionsProvider).value ??
        const <FinancialDecision>[];
    return AppPageScaffold(
      title: l10n.lifeEventScenariosTitle,
      childPad: false,
      child: baseline == null
          ? AppEmptyState(
              icon: FLucideIcons.waypoints,
              title: l10n.lifeEventScenariosEmptyTitle,
              message: l10n.lifeEventScenariosEmptyBody,
              action: FButton(
                onPress: () => context.push(FinanceRoutes.planRunway),
                child: Text(l10n.moneyRunwayTitle),
              ),
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
                const SizedBox(height: AppSpacing.s12),
                AppAdaptiveChoice<LifeEventTemplate>(
                  title: l10n.lifeEventScenariosTitle,
                  options: LifeEventTemplate.values,
                  value: _selectedTemplate,
                  labelOf: (template) => _templateLabel(l10n, template),
                  inlineMaxOptions: 2,
                  iconOf: (template) => switch (template) {
                    LifeEventTemplate.largePurchase => FLucideIcons.shoppingBag,
                    LifeEventTemplate.careerBreak => FLucideIcons.briefcase,
                    LifeEventTemplate.homePurchase => FLucideIcons.house,
                  },
                  onChanged: (template) =>
                      setState(() => _selectedTemplate = template),
                ),
                const SizedBox(height: AppSpacing.s16),
                _ScenarioCard(
                  key: ValueKey(_selectedTemplate),
                  template: _selectedTemplate,
                  baseline: baseline,
                ),
                if (decisions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s12),
                  _DecisionHistory(decisions: decisions, baseline: baseline),
                ],
              ],
            ),
    );
  }
}

class _DecisionHistory extends StatefulWidget {
  const _DecisionHistory({required this.decisions, required this.baseline});

  final List<FinancialDecision> decisions;
  final LifeEventBaseline baseline;

  @override
  State<_DecisionHistory> createState() => _DecisionHistoryState();
}

class _DecisionHistoryState extends State<_DecisionHistory> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDisclosureHeader(
          title: l10n.lifeEventDecisionHistory,
          expanded: _open,
          onToggle: () => setState(() => _open = !_open),
        ),
        AnimatedSizeFade(
          visible: _open,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: Column(
              children: [
                for (final decision in widget.decisions)
                  _DecisionRow(decision: decision, baseline: widget.baseline),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScenarioCard extends ConsumerStatefulWidget {
  const _ScenarioCard({
    super.key,
    required this.template,
    required this.baseline,
  });

  final LifeEventTemplate template;
  final LifeEventBaseline baseline;

  @override
  ConsumerState<_ScenarioCard> createState() => _ScenarioCardState();
}

class _ScenarioCardState extends ConsumerState<_ScenarioCard> {
  LifeEventAssumptions? _editedAssumptions;
  LifeEventVariant _selectedVariant = LifeEventVariant.baseline;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = context.formatters(ref);
    const engine = LifeEventScenarioEngine();
    final baseAssumptions =
        _editedAssumptions ?? engine.preset(widget.template, widget.baseline);
    final assumptions = engine.variant(baseAssumptions, _selectedVariant);
    final outcome = engine.simulate(widget.baseline, assumptions);
    final exactFireDelay = _exactFireDelayMonths(
      ref,
      widget.baseline,
      assumptions,
      engine,
    );
    final groundedOutcome = exactFireDelay == null
        ? outcome
        : outcome.withFireDelay(exactFireDelay);
    Widget variantTile(LifeEventVariant variant) {
      return Semantics(
        selected: variant == _selectedVariant,
        child: SoftCard.flat(
          onPress: () => setState(() => _selectedVariant = variant),
          padding: const EdgeInsets.all(AppSpacing.s8),
          child: Column(
            children: [
              Text(
                _variantLabel(l10n, variant),
                style: context.captionStyle.copyWith(
                  color: variant == _selectedVariant
                      ? context.theme.colors.primary
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                formatter.compactCurrency(
                  engine
                      .simulate(
                        widget.baseline,
                        engine.variant(baseAssumptions, variant),
                      )
                      .liquidAfter90Days,
                  code: widget.baseline.currency,
                ),
                style: TypographyTokens.numericCaptionStrong,
              ),
            ],
          ),
        ),
      );
    }

    return SoftCard.raised(
      padding: AppPageRhythm.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _templateLabel(l10n, widget.template),
            style: context.rowTitleStyle,
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            _assumptionCopy(
              l10n,
              widget.template,
              baseAssumptions.durationMonths,
            ),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < Breakpoints.compactContent ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = 0;
                      index < LifeEventVariant.values.length;
                      index++
                    ) ...[
                      if (index > 0) const SizedBox(height: AppSpacing.s6),
                      variantTile(LifeEventVariant.values[index]),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (
                    var index = 0;
                    index < LifeEventVariant.values.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(width: AppSpacing.s6),
                    Expanded(
                      child: variantTile(LifeEventVariant.values[index]),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          _MetricRow(
            label: l10n.lifeEventAfter90Days,
            value: formatter.currency(
              outcome.liquidAfter90Days,
              code: widget.baseline.currency,
            ),
          ),
          _MetricRow(
            label: l10n.lifeEventAfter12Months,
            value: formatter.currency(
              outcome.liquidAfter12Months,
              code: widget.baseline.currency,
            ),
          ),
          _MetricRow(
            label: l10n.lifeEventMonthlySurplus,
            value: formatter.currency(
              outcome.monthlySurplus,
              code: widget.baseline.currency,
            ),
          ),
          if (exactFireDelay != null)
            _MetricRow(
              label: l10n.lifeEventFireImpact,
              value: exactFireDelay <= 0
                  ? l10n.lifeEventFireNoDelay
                  : l10n.lifeEventFireDelay(exactFireDelay),
            ),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: () async {
              final edited = await _editAssumptions(
                context,
                l10n,
                baseAssumptions,
              );
              if (edited != null && mounted) {
                setState(() => _editedAssumptions = edited);
              }
            },
            child: Text(l10n.lifeEventEditAssumptions),
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
                    objectLabel: _templateLabel(l10n, widget.template),
                    attrs: {
                      'template': widget.template.name,
                      'assumptions': assumptions.toJson(),
                      'deterministic_outcome': groundedOutcome.toJson(),
                      'fire_delay_months': exactFireDelay,
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
                  onPress: _saving
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final reviewDate = await _chooseReviewDate(
                            context,
                            now,
                          );
                          if (reviewDate == null || !mounted) return;
                          setState(() => _saving = true);
                          try {
                            await ref
                                .read(productMetricsProvider.notifier)
                                .record(ProductFunnelEvent.lifeEventCompared);
                            final repository = await ref.read(
                              financialDecisionRepositoryProvider.future,
                            );
                            final decision = await repository.create(
                              template: widget.template,
                              selectedVariant: _selectedVariant,
                              baseline: widget.baseline,
                              assumptions: assumptions,
                              outcome: groundedOutcome,
                              reviewDate: reviewDate,
                              now: now,
                            );
                            final actionId =
                                await ref.read(lifeActionDispatcherProvider)(
                                  LifeActionDraft(
                                    title: l10n.lifeEventReviewActionTitle(
                                      _templateLabel(l10n, widget.template),
                                    ),
                                    note: l10n.lifeEventReviewActionBody,
                                    sourceDomain: 'finance',
                                    sourceRowFamily: 'financial_decisions',
                                    sourceRowId: decision.id,
                                    dueAt: decision.reviewDate,
                                  ),
                                );
                            if (actionId != null) {
                              await repository.linkAction(
                                id: decision.id,
                                actionId: actionId,
                              );
                            }
                            await ref
                                .read(productMetricsProvider.notifier)
                                .record(
                                  ProductFunnelEvent.financialDecisionSaved,
                                );
                            if (context.mounted) {
                              AppMessenger.show(
                                context,
                                ToastKind.success,
                                l10n.lifeEventDecisionSaved,
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              AppMessenger.show(
                                context,
                                ToastKind.error,
                                l10n.commonSaveFailed,
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _saving = false);
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
                onPress: decision.reviewDate.isAfter(DateTime.now())
                    ? null
                    : () async {
                        final actual = const LifeEventScenarioEngine().observe(
                          baseline,
                        );
                        final repository = await ref.read(
                          financialDecisionRepositoryProvider.future,
                        );
                        await repository.review(
                          id: decision.id,
                          actualOutcome: actual,
                          evidence: FinancialDecisionReviewEvidence(
                            observedAt: DateTime.now(),
                            sourceRowFamilies: const <String>[
                              'fin:accounts',
                              'fin:journal_entries',
                              'fin:financial_decisions',
                            ],
                            dataCompleteness:
                                ref
                                    .read(moneyRunwayProvider)
                                    .value
                                    ?.dataCompleteness ??
                                0,
                          ),
                          now: DateTime.now(),
                        );
                        await ref
                            .read(productMetricsProvider.notifier)
                            .record(
                              ProductFunnelEvent.financialDecisionReviewed,
                            );
                        if (context.mounted) {
                          AppMessenger.show(
                            context,
                            ToastKind.success,
                            l10n.lifeEventReviewed,
                          );
                        }
                      },
                child: Text(l10n.lifeEventCaptureActual),
              ),
            ],
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                if (decision.actionId case final actionId?)
                  FButton(
                    variant: FButtonVariant.outline,
                    onPress: () {
                      final routeBuilder = ref.read(
                        lifeActionRouteBuilderProvider,
                      );
                      if (routeBuilder != null) {
                        context.push(routeBuilder(actionId));
                      }
                    },
                    child: Text(l10n.lifeEventOpenAction),
                  ),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () =>
                      context.push(_adjustmentRouteFor(decision.template)),
                  child: Text(l10n.lifeEventAdjustPlan),
                ),
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: () async {
                    final repository = await ref.read(
                      financialDecisionRepositoryProvider.future,
                    );
                    await repository.remove(decision.id);
                    if (context.mounted) {
                      AppMessenger.show(
                        context,
                        ToastKind.success,
                        l10n.commonDeleted,
                      );
                    }
                  },
                  child: Text(l10n.commonDelete),
                ),
              ],
            ),
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

Future<DateTime?> _chooseReviewDate(BuildContext context, DateTime now) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<DateTime>(
    context: context,
    title: l10n.lifeEventChooseReviewDate,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in <(int, String)>[
          (30, l10n.lifeEventReviewIn30Days),
          (90, l10n.lifeEventReviewIn90Days),
          (180, l10n.lifeEventReviewIn180Days),
        ]) ...[
          FButton(
            variant: option.$1 == 90
                ? FButtonVariant.primary
                : FButtonVariant.outline,
            onPress: () => Navigator.of(
              sheetContext,
            ).pop(now.add(Duration(days: option.$1))),
            child: Text(option.$2),
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
      ],
    ),
  );
}

String _adjustmentRouteFor(LifeEventTemplate template) => switch (template) {
  LifeEventTemplate.largePurchase => FinanceRoutes.planBudget,
  LifeEventTemplate.careerBreak => FinanceRoutes.planRunway,
  LifeEventTemplate.homePurchase => FinanceRoutes.wealthLiabilities,
};

String _templateLabel(AppLocalizations l10n, LifeEventTemplate template) =>
    switch (template) {
      LifeEventTemplate.largePurchase => l10n.lifeEventLargePurchase,
      LifeEventTemplate.careerBreak => l10n.lifeEventCareerBreak,
      LifeEventTemplate.homePurchase => l10n.lifeEventHomePurchase,
    };

String _variantLabel(AppLocalizations l10n, LifeEventVariant variant) =>
    switch (variant) {
      LifeEventVariant.optimistic => l10n.lifeEventOptimistic,
      LifeEventVariant.baseline => l10n.lifeEventBaseline,
      LifeEventVariant.conservative => l10n.lifeEventConservative,
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

Future<LifeEventAssumptions?> _editAssumptions(
  BuildContext context,
  AppLocalizations l10n,
  LifeEventAssumptions current,
) {
  return showAppFormSheet<LifeEventAssumptions>(
    context: context,
    builder: (_) => _LifeEventAssumptionsSheet(l10n: l10n, current: current),
  );
}

class _LifeEventAssumptionsSheet extends StatefulWidget {
  const _LifeEventAssumptionsSheet({required this.l10n, required this.current});

  final AppLocalizations l10n;
  final LifeEventAssumptions current;

  @override
  State<_LifeEventAssumptionsSheet> createState() =>
      _LifeEventAssumptionsSheetState();
}

class _LifeEventAssumptionsSheetState
    extends State<_LifeEventAssumptionsSheet> {
  late final TextEditingController _upfront;
  late final TextEditingController _income;
  late final TextEditingController _outflow;
  late final TextEditingController _duration;
  String? _error;

  @override
  void initState() {
    super.initState();
    _upfront = TextEditingController(
      text: widget.current.upfrontCost.toString(),
    );
    _income = TextEditingController(
      text: widget.current.monthlyIncomeDelta.toString(),
    );
    _outflow = TextEditingController(
      text: widget.current.monthlyOutflowDelta.toString(),
    );
    _duration = TextEditingController(
      text: widget.current.durationMonths.toString(),
    );
  }

  @override
  void dispose() {
    _upfront.dispose();
    _income.dispose();
    _outflow.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    const signedNumber = TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    );
    return AppSheet(
      title: l10n.lifeEventEditAssumptions,
      footer: AppSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        onSubmit: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(controller: _upfront),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.lifeEventUpfrontCost),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _income),
            keyboardType: signedNumber,
            label: Text(l10n.lifeEventIncomeDelta),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _outflow),
            keyboardType: signedNumber,
            label: Text(l10n.lifeEventOutflowDelta),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _duration),
            keyboardType: TextInputType.number,
            label: Text(l10n.lifeEventDurationMonths),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(kind: AppStatusKind.error, message: _error!),
          ],
        ],
      ),
    );
  }

  void _save() {
    final parsedUpfront = Decimal.tryParse(_upfront.text.trim());
    final parsedIncome = Decimal.tryParse(_income.text.trim());
    final parsedOutflow = Decimal.tryParse(_outflow.text.trim());
    final parsedDuration = int.tryParse(_duration.text.trim());
    if (parsedUpfront == null ||
        parsedIncome == null ||
        parsedOutflow == null ||
        parsedDuration == null ||
        parsedDuration < 1) {
      setState(() => _error = widget.l10n.commonInvalidNumber);
      return;
    }
    Navigator.of(context).pop(
      LifeEventAssumptions(
        upfrontCost: parsedUpfront,
        monthlyIncomeDelta: parsedIncome,
        monthlyOutflowDelta: parsedOutflow,
        durationMonths: parsedDuration,
      ),
    );
  }
}

int? _exactFireDelayMonths(
  WidgetRef ref,
  LifeEventBaseline baseline,
  LifeEventAssumptions assumptions,
  LifeEventScenarioEngine engine,
) {
  final view = ref.watch(fireDashboardViewProvider).value;
  if (view == null || view.goal.targetAmount <= Decimal.zero) return null;
  final base = view.scenarios
      .where((scenario) => scenario.tier == FireScenarioTier.neutral)
      .firstOrNull;
  if (base?.monthsToTarget == null) return null;
  final duration = assumptions.durationMonths;
  final normalAtEnd =
      baseline.liquidBalance +
      (baseline.monthlyIncome - baseline.monthlyOutflow) *
          Decimal.fromInt(duration);
  final eventAtEnd = engine.balanceAfterMonths(baseline, assumptions, duration);
  final adjusted = ref
      .watch(fireCalculatorProvider)
      .buildView(
        goal: view.goal,
        currentNetWorth: view.currentNetWorth + eventAtEnd - normalAtEnd,
        baseCurrency: view.baseCurrency,
        start: view.start.add(Duration(days: duration * 30)),
      );
  final scenario = adjusted.scenarios
      .where((item) => item.tier == FireScenarioTier.neutral)
      .firstOrNull;
  final adjustedMonths = scenario?.monthsToTarget;
  if (adjustedMonths == null) return null;
  return duration + adjustedMonths - base!.monthsToTarget!;
}
