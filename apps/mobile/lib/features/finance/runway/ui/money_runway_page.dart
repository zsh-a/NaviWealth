import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/lifeos/action_dispatcher.dart';
import 'package:naviwealth/core/product/product_metrics.dart';
import 'package:naviwealth/core/shell/settings_route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/money_runway_providers.dart';
import '../domain/money_runway.dart';

class MoneyRunwayPage extends ConsumerWidget {
  const MoneyRunwayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.listen(moneyRunwayProvider, (_, next) {
      final snapshot = next.value;
      if (snapshot == null || !snapshot.hasData) return;
      unawaited(
        ref
            .read(runwayForecastRepositoryProvider.future)
            .then((repository) => repository.recordAndEvaluate(snapshot)),
      );
    });
    final runway = ref.watch(moneyRunwayProvider);
    return AppPageScaffold(
      title: l10n.moneyRunwayTitle,
      childPad: false,
      child: runway.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(
            context,
            error,
            operation: 'load money runway',
          ),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(moneyRunwayProvider),
        ),
        data: (snapshot) => _RunwayContent(snapshot: snapshot),
      ),
    );
  }
}

class _RunwayContent extends ConsumerWidget {
  const _RunwayContent({required this.snapshot});

  final MoneyRunwaySnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    if (!snapshot.hasData) {
      return AppEmptyState(
        icon: FLucideIcons.calendarRange,
        title: l10n.moneyRunwayEmptyTitle,
        message: l10n.moneyRunwayEmptyBody,
        action: Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          alignment: WrapAlignment.center,
          children: [
            FButton(
              onPress: () => context.push(FinanceRoutes.wealthNewCash),
              child: Text(l10n.assetsAddCashTitle),
            ),
            FButton(
              variant: FButtonVariant.outline,
              onPress: () => context.push(FinanceRoutes.cashflowRecurring),
              child: Text(l10n.recurringListTitle),
            ),
          ],
        ),
      );
    }
    final status = _statusCopy(l10n, snapshot.status);
    final statusColor = switch (snapshot.status) {
      MoneyRunwayStatus.healthy => SemanticColors.of(context).success,
      MoneyRunwayStatus.watch => SemanticColors.of(context).warning,
      MoneyRunwayStatus.shortfall => context.theme.colors.destructive,
    };
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        SoftCard.hero(
          padding: AppPageRhythm.heroPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.moneyRunwayNinetyDayBalance,
                      style: context.mutedLabelStyle,
                    ),
                  ),
                  AppBadge(
                    label: status.$1,
                    size: AppBadgeSize.compact,
                    foregroundColor: statusColor,
                    containerColor: statusColor.withValues(
                      alpha: AppOpacity.subtle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s10),
              Text(
                formatters.currency(
                  snapshot.balanceAt(90),
                  code: snapshot.currency,
                ),
                style: TypographyTokens.displayLarge,
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(status.$2, style: context.bodyCaptionStyle),
              const SizedBox(height: AppSpacing.s12),
              Text(
                l10n.moneyRunwayConfidence(
                  _confidenceLabel(l10n, snapshot.confidence),
                ),
                style: context.captionStyle,
              ),
              if (snapshot.status != MoneyRunwayStatus.healthy) ...[
                const SizedBox(height: AppSpacing.s12),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () =>
                      _createRunwayAction(context, ref, l10n, snapshot),
                  child: Text(l10n.moneyRunwayCreateAction),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        Text(l10n.moneyRunwayHorizonsTitle, style: context.mutedLabelStyle),
        const SizedBox(height: AppSpacing.s8),
        _RunwayHorizonGrid(
          formatValue: (days) => formatters.compactCurrency(
            snapshot.balanceAt(days),
            code: snapshot.currency,
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        _ScenarioSection(snapshot: snapshot),
        const SizedBox(height: AppSpacing.s16),
        SoftCard.raised(
          borderless: true,
          padding: const EdgeInsets.all(AppSpacing.s14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.moneyRunwayAssumptionsTitle, style: context.labelStyle),
              const SizedBox(height: AppSpacing.s10),
              _ValueRow(
                label: l10n.moneyRunwayStartingCash,
                value: formatters.currency(
                  snapshot.startingBalance,
                  code: snapshot.currency,
                ),
              ),
              _ValueRow(
                label: l10n.moneyRunwayReserveTarget,
                value:
                    '${formatters.currency(snapshot.reserveTarget, code: snapshot.currency)}'
                    ' · ${_assumptionSourceLabel(l10n, snapshot.reserveSource)}',
              ),
              _ValueRow(
                label: l10n.moneyRunwayVariableEstimate,
                value:
                    '${formatters.currency(snapshot.estimatedDailyVariableOutflow * Decimal.fromInt(30), code: snapshot.currency)}'
                    ' · ${_assumptionSourceLabel(l10n, snapshot.monthlyExpenseSource)}',
              ),
              _ValueRow(
                label: l10n.moneyRunwayCoverage,
                value: snapshot.emergencyCoverageMonths == null
                    ? l10n.commonNotAvailable
                    : l10n.moneyRunwayCoverageMonths(
                        snapshot.emergencyCoverageMonths!.toStringAsFixed(1),
                      ),
              ),
              _ValueRow(
                label: l10n.moneyRunwayCompleteness,
                value:
                    '${(snapshot.dataCompleteness * 100).toStringAsFixed(0)}%',
              ),
              if (snapshot.historicalForecastError != null)
                _ValueRow(
                  label: l10n.moneyRunwayHistoricalError,
                  value:
                      '${(snapshot.historicalForecastError! * 100).toStringAsFixed(1)}%',
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        Text(l10n.moneyRunwayScheduledTitle, style: context.mutedLabelStyle),
        const SizedBox(height: AppSpacing.s8),
        if (snapshot.scheduledFlows.isEmpty)
          SoftCard.flat(
            padding: const EdgeInsets.all(AppSpacing.s14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.moneyRunwayScheduledEmpty,
                  style: context.captionStyle,
                ),
                const SizedBox(height: AppSpacing.s8),
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: () => context.push(FinanceRoutes.cashflowRecurring),
                  child: Text(l10n.recurringListTitle),
                ),
              ],
            ),
          )
        else
          SoftCard.flat(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < snapshot.scheduledFlows.length; i++) ...[
                  _ScheduledFlowRow(flow: snapshot.scheduledFlows[i]),
                  if (i < snapshot.scheduledFlows.length - 1)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
        if (snapshot.missingCurrencies.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.moneyRunwayMissingFx(
              (snapshot.missingCurrencies.toList()..sort()).join(', '),
            ),
            style: context.captionStyle.copyWith(
              color: SemanticColors.of(context).warning,
            ),
          ),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: () => context.push(SettingsRoutes.fxRates),
            child: Text(l10n.settingsFxRatesTitle),
          ),
        ],
      ],
    );
  }
}

class _RunwayHorizonGrid extends StatelessWidget {
  const _RunwayHorizonGrid({required this.formatValue});

  final String Function(int days) formatValue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cards = [
      for (final days in const [30, 60, 90])
        SoftCard.flat(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.moneyRunwayDays(days), style: context.captionStyle),
              const SizedBox(height: AppSpacing.s6),
              Text(
                formatValue(days),
                style: TypographyTokens.numericTitleStrong,
              ),
            ],
          ),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < 420 || textScale > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.s8),
                cards[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.s8),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }
}

class _ScenarioSection extends ConsumerStatefulWidget {
  const _ScenarioSection({required this.snapshot});

  final MoneyRunwaySnapshot snapshot;

  @override
  ConsumerState<_ScenarioSection> createState() => _ScenarioSectionState();
}

class _ScenarioSectionState extends ConsumerState<_ScenarioSection> {
  MoneyRunwaySnapshot? _customResult;
  _CustomRunwayScenario? _customInput;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = context.formatters(ref);
    final scenarios = <(String, MoneyRunwaySnapshot)>[
      (
        l10n.moneyRunwayScenarioPurchase,
        applyMoneyRunwayScenario(
          widget.snapshot,
          MoneyRunwayScenario.largePurchase(
            widget.snapshot.averageMonthlyExpense,
          ),
        ),
      ),
      (
        l10n.moneyRunwayScenarioDelayedIncome,
        applyMoneyRunwayScenario(
          widget.snapshot,
          MoneyRunwayScenario.delayedIncome(14),
        ),
      ),
      (
        l10n.moneyRunwayScenarioReducedIncome,
        applyMoneyRunwayScenario(
          widget.snapshot,
          MoneyRunwayScenario.reducedIncome(reduction: Decimal.parse('0.3')),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.moneyRunwayScenariosTitle, style: context.mutedLabelStyle),
        const SizedBox(height: AppSpacing.s8),
        for (final scenario in scenarios) ...[
          SoftCard.flat(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Row(
              children: [
                Expanded(child: Text(scenario.$1, style: context.labelStyle)),
                Text(
                  formatter.compactCurrency(
                    scenario.$2.minimumExpectedBalance,
                    code: scenario.$2.currency,
                  ),
                  style: TypographyTokens.numericBodyStrong,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
        FButton(
          variant: FButtonVariant.outline,
          onPress: _configureCustomScenario,
          child: Text(l10n.moneyRunwayCustomScenarioAction),
        ),
        if (_customResult case final result?) ...[
          const SizedBox(height: AppSpacing.s8),
          SoftCard.raised(
            borderless: true,
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.moneyRunwayCustomResult,
                        style: context.labelStyle,
                      ),
                    ),
                    Text(
                      formatter.compactCurrency(
                        result.minimumExpectedBalance,
                        code: result.currency,
                      ),
                      style: TypographyTokens.numericBodyStrong,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  _statusCopy(l10n, result.status).$2,
                  style: context.captionStyle,
                ),
                const SizedBox(height: AppSpacing.s6),
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [
                    FButton(
                      variant: FButtonVariant.outline,
                      onPress: () => _createRunwayAction(
                        context,
                        ref,
                        l10n,
                        result,
                        scenario: _customInput?.toEvidenceJson(),
                      ),
                      child: Flexible(
                        child: Text(
                          l10n.moneyRunwayCreateAction,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    FButton(
                      variant: FButtonVariant.ghost,
                      onPress: () => setState(() {
                        _customResult = null;
                        _customInput = null;
                      }),
                      child: Flexible(
                        child: Text(
                          l10n.moneyRunwayCustomReset,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _configureCustomScenario() async {
    final input = await _showCustomScenarioDialog(context, widget.snapshot);
    if (input == null || !mounted) return;
    var result = widget.snapshot;
    if (input.purchaseAmount > Decimal.zero) {
      result = applyMoneyRunwayScenario(
        result,
        MoneyRunwayScenario.largePurchase(input.purchaseAmount),
      );
    }
    if (input.incomeDelayDays > 0) {
      result = applyMoneyRunwayScenario(
        result,
        MoneyRunwayScenario.delayedIncome(input.incomeDelayDays),
      );
    }
    if (input.incomeReduction > Decimal.zero) {
      result = applyMoneyRunwayScenario(
        result,
        MoneyRunwayScenario.reducedIncome(
          reduction: input.incomeReduction,
          durationDays: input.reductionDurationDays,
        ),
      );
    }
    setState(() {
      _customResult = result;
      _customInput = input;
    });
  }
}

final class _CustomRunwayScenario {
  const _CustomRunwayScenario({
    required this.purchaseAmount,
    required this.incomeDelayDays,
    required this.incomeReduction,
    required this.reductionDurationDays,
  });

  final Decimal purchaseAmount;
  final int incomeDelayDays;
  final Decimal incomeReduction;
  final int reductionDurationDays;

  Map<String, Object?> toEvidenceJson() => <String, Object?>{
    'purchase_amount': purchaseAmount.toString(),
    'income_delay_days': incomeDelayDays,
    'income_reduction': incomeReduction.toString(),
    'reduction_duration_days': reductionDurationDays,
  };
}

Future<_CustomRunwayScenario?> _showCustomScenarioDialog(
  BuildContext context,
  MoneyRunwaySnapshot snapshot,
) {
  return showAppFormSheet<_CustomRunwayScenario>(
    context: context,
    builder: (_) => _CustomRunwayScenarioSheet(snapshot: snapshot),
  );
}

class _CustomRunwayScenarioSheet extends StatefulWidget {
  const _CustomRunwayScenarioSheet({required this.snapshot});

  final MoneyRunwaySnapshot snapshot;

  @override
  State<_CustomRunwayScenarioSheet> createState() =>
      _CustomRunwayScenarioSheetState();
}

class _CustomRunwayScenarioSheetState
    extends State<_CustomRunwayScenarioSheet> {
  late final TextEditingController _purchase;
  late final TextEditingController _delay;
  late final TextEditingController _reduction;
  late final TextEditingController _duration;
  String? _error;

  @override
  void initState() {
    super.initState();
    _purchase = TextEditingController(
      text: widget.snapshot.averageMonthlyExpense.toString(),
    );
    _delay = TextEditingController(text: '14');
    _reduction = TextEditingController(text: '30');
    _duration = TextEditingController(text: '90');
  }

  @override
  void dispose() {
    _purchase.dispose();
    _delay.dispose();
    _reduction.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.moneyRunwayCustomScenarioTitle,
      footer: AppSheetFooter(
        submitLabel: l10n.moneyRunwayCustomRun,
        cancelLabel: l10n.commonCancel,
        onSubmit: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(controller: _purchase),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(
              l10n.moneyRunwayCustomPurchase(widget.snapshot.currency),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _delay),
            keyboardType: TextInputType.number,
            label: Text(l10n.moneyRunwayCustomDelayDays),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _reduction),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.moneyRunwayCustomReductionPercent),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _duration),
            keyboardType: TextInputType.number,
            label: Text(l10n.moneyRunwayCustomDurationDays),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(kind: AppStatusKind.error, message: _error!),
          ],
        ],
      ),
    );
  }

  void _submit() {
    final purchaseAmount = Decimal.tryParse(_purchase.text.trim());
    final delayDays = int.tryParse(_delay.text.trim());
    final reductionPercent = Decimal.tryParse(_reduction.text.trim());
    final durationDays = int.tryParse(_duration.text.trim());
    if (purchaseAmount == null ||
        purchaseAmount < Decimal.zero ||
        delayDays == null ||
        delayDays < 0 ||
        reductionPercent == null ||
        reductionPercent < Decimal.zero ||
        reductionPercent > Decimal.fromInt(100) ||
        durationDays == null ||
        durationDays <= 0 ||
        (purchaseAmount == Decimal.zero &&
            delayDays == 0 &&
            reductionPercent == Decimal.zero)) {
      setState(
        () => _error = AppLocalizations.of(context).moneyRunwayCustomInvalid,
      );
      return;
    }
    Navigator.of(context).pop(
      _CustomRunwayScenario(
        purchaseAmount: purchaseAmount,
        incomeDelayDays: delayDays,
        incomeReduction: (reductionPercent / Decimal.fromInt(100)).toDecimal(
          scaleOnInfinitePrecision: 4,
        ),
        reductionDurationDays: durationDays,
      ),
    );
  }
}

class _ScheduledFlowRow extends ConsumerWidget {
  const _ScheduledFlowRow({required this.flow});

  final RunwayScheduledFlow flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatter = context.formatters(ref);
    final label = flow.kind == RunwayFlowKind.dividend
        ? flow.certainty == RunwayFlowCertainty.known
              ? l10n.moneyRunwayDeclaredDividend
              : l10n.moneyRunwayEstimatedDividend
        : flow.label;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  flow.certainty == RunwayFlowCertainty.estimated
                      ? '${formatter.date(flow.date.toLocal())} · ${l10n.moneyRunwayEstimatedFlow}'
                      : formatter.date(flow.date.toLocal()),
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          Text(
            formatter.currency(flow.amount),
            style: TypographyTokens.numericBodyStrong,
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: context.captionStyle)),
        const SizedBox(width: AppSpacing.s12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: context.labelStyle,
          ),
        ),
      ],
    ),
  );
}

(String, String) _statusCopy(AppLocalizations l10n, MoneyRunwayStatus status) =>
    switch (status) {
      MoneyRunwayStatus.healthy => (
        l10n.moneyRunwayStatusHealthy,
        l10n.moneyRunwayStatusHealthyBody,
      ),
      MoneyRunwayStatus.watch => (
        l10n.moneyRunwayStatusWatch,
        l10n.moneyRunwayStatusWatchBody,
      ),
      MoneyRunwayStatus.shortfall => (
        l10n.moneyRunwayStatusShortfall,
        l10n.moneyRunwayStatusShortfallBody,
      ),
    };

String _confidenceLabel(
  AppLocalizations l10n,
  MoneyRunwayConfidence confidence,
) => switch (confidence) {
  MoneyRunwayConfidence.low => l10n.moneyRunwayConfidenceLow,
  MoneyRunwayConfidence.medium => l10n.moneyRunwayConfidenceMedium,
  MoneyRunwayConfidence.high => l10n.moneyRunwayConfidenceHigh,
};

String _assumptionSourceLabel(
  AppLocalizations l10n,
  MoneyRunwayAssumptionSource source,
) => switch (source) {
  MoneyRunwayAssumptionSource.observedHistory =>
    l10n.moneyRunwaySourceObservedHistory,
  MoneyRunwayAssumptionSource.firePlan => l10n.moneyRunwaySourceFirePlan,
  MoneyRunwayAssumptionSource.defaultPolicy =>
    l10n.moneyRunwaySourceDefaultPolicy,
};

Future<void> _createRunwayAction(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  MoneyRunwaySnapshot snapshot, {
  Map<String, Object?>? scenario,
}) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(l10n.moneyRunwayActionConfirmTitle),
    body: Text(l10n.moneyRunwayActionConfirmBody),
    confirmLabel: l10n.commonConfirm,
    cancelLabel: l10n.commonCancel,
    icon: FLucideIcons.listTodo,
  );
  if (confirmed != true || !context.mounted) return;
  final dispatch = ref.read(lifeActionDispatcherProvider);
  final evidence = <String, Object?>{...snapshot.toEvidenceJson()};
  if (scenario != null) evidence['scenario'] = scenario;
  final id = await dispatch(
    LifeActionDraft(
      title: l10n.moneyRunwayActionTitle,
      note: jsonEncode(evidence),
      sourceDomain: 'finance',
      sourceRowFamily: 'money_runway',
      sourceRowId: scenario == null ? 'current' : 'custom-scenario',
      priority: snapshot.status == MoneyRunwayStatus.shortfall
          ? 'high'
          : 'normal',
      dueAt: snapshot.firstShortfallDate,
    ),
  );
  if (context.mounted && id != null) {
    unawaited(
      ref
          .read(productMetricsProvider.notifier)
          .record(ProductFunnelEvent.executionActionCreated, success: true),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.moneyRunwayActionCreated)));
    final routeBuilder = ref.read(lifeActionRouteBuilderProvider);
    if (routeBuilder != null && context.mounted) {
      await context.push<void>(routeBuilder(id));
    }
  }
}
