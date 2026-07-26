import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../application/dca_simulation_service.dart';
import '../application/dca_trade_entry_prefills.dart';
import '../data/dca_plan_providers.dart';
import '../domain/dca/dca_plan.dart';
import '../domain/dca/dca_simulator.dart';
import 'trade_entry_form_page.dart';

class DcaSimulatorPage extends ConsumerStatefulWidget {
  const DcaSimulatorPage({super.key});

  @override
  ConsumerState<DcaSimulatorPage> createState() => _DcaSimulatorPageState();
}

class _DcaSimulatorPageState extends ConsumerState<DcaSimulatorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _symbols;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  AssetMarket _market = AssetMarket.usStock;
  DcaFrequency _frequency = DcaFrequency.monthly;
  int _years = 5;

  @override
  void initState() {
    super.initState();
    _symbols = TextEditingController(text: 'VOO');
    _amount = TextEditingController(text: '500');
    _currency = TextEditingController(text: 'USD');
  }

  @override
  void dispose() {
    _symbols.dispose();
    _amount.dispose();
    _currency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(dcaSimulationProvider);
    final plans = ref.watch(dcaPlansProvider);
    return AppPageScaffold(
      title: l10n.dcaSimulatorTitle,
      actions: [
        AppHeaderAction(
          semanticsLabel: l10n.commonRefresh,
          icon: const Icon(FLucideIcons.refreshCw),
          onPress: () => ref.read(dcaSimulationProvider.notifier).refresh(),
        ),
      ],
      childPad: false,
      child: ListView(
        padding: shellTabContentPadding(
          context,
          left: Breakpoints.isMobile(MediaQuery.sizeOf(context).width)
              ? AppSpacing.s16
              : AppSpacing.s24,
          top: AppSpacing.s8,
          right: Breakpoints.isMobile(MediaQuery.sizeOf(context).width)
              ? AppSpacing.s16
              : AppSpacing.s24,
        ),
        children: [
          _DcaPlansSection(
            plans: plans,
            onExecute: _executePlan,
            onToggle: _togglePlan,
            onDelete: _deletePlan,
          ),
          const SizedBox(height: AppSpacing.s16),
          _DcaControls(
            formKey: _formKey,
            symbols: _symbols,
            amount: _amount,
            currency: _currency,
            market: _market,
            frequency: _frequency,
            years: _years,
            busy: state.isLoading,
            onMarketChanged: (value) => setState(() => _market = value),
            onFrequencyChanged: (value) => setState(() => _frequency = value),
            onYearsChanged: (value) => setState(() => _years = value),
            onRun: _run,
          ),
          const SizedBox(height: AppSpacing.s16),
          state.when(
            loading: () => const SkeletonBox(height: 360, radius: 8),
            error: (error, stackTrace) =>
                kDefaultError(context, error, stackTrace),
            data: (data) =>
                _DcaResults(state: data, onDraft: () => _savePlan(data)),
          ),
        ],
      ),
    );
  }

  Future<void> _run() async {
    if (!_formKey.currentState!.validate()) return;
    final request = DcaSimulationRequest(
      symbols: _parseSymbols(_symbols.text),
      market: _market,
      amountPerContribution: Decimal.parse(_amount.text.trim()),
      currency: _currency.text.trim().toUpperCase(),
      years: _years,
      frequency: _frequency,
    );
    await ref.read(dcaSimulationProvider.notifier).run(request);
  }

  Future<void> _savePlan(DcaSimulationState state) async {
    final allocations = _parseAllocations(_symbols.text);
    if (allocations.isEmpty) return;
    final now = DateTime.now().toUtc();
    try {
      final repository = await ref.read(dcaPlanRepositoryProvider.future);
      await repository.create(
        allocations: allocations,
        amountPerContribution: state.request.amountPerContribution,
        currency: state.request.currency,
        market: state.request.market,
        frequency: state.request.frequency,
        nextDueAt: now,
        endAt: DateTime.utc(now.year + state.request.years, now.month, now.day),
      );
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          AppLocalizations.of(context).dcaPlanSaved,
        );
      }
    } catch (_) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).commonSaveFailed,
        );
      }
    }
  }

  Future<void> _executePlan(DcaPlan plan) async {
    final completed = await _openContribution(
      allocations: plan.allocations,
      amountPerContribution: plan.amountPerContribution,
      currency: plan.currency,
      market: plan.market,
    );
    if (!completed || !mounted) return;
    try {
      final repository = await ref.read(dcaPlanRepositoryProvider.future);
      await repository.markExecuted(plan, DateTime.now().toUtc());
    } catch (_) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).commonSaveFailed,
        );
      }
    }
  }

  Future<void> _togglePlan(DcaPlan plan) async {
    try {
      final repository = await ref.read(dcaPlanRepositoryProvider.future);
      await repository.setEnabled(plan, !plan.enabled);
    } catch (_) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).commonSaveFailed,
        );
      }
    }
  }

  Future<void> _deletePlan(DcaPlan plan) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.dcaPlanDeleteTitle),
      body: Text(l10n.dcaPlanDeleteBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    try {
      final repository = await ref.read(dcaPlanRepositoryProvider.future);
      await repository.remove(plan);
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonDeleteFailed);
      }
    }
  }

  Future<bool> _openContribution({
    required List<DcaAllocation> allocations,
    required Decimal amountPerContribution,
    required String currency,
    required AssetMarket market,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (allocations.isEmpty) return false;
    final prefills = buildDcaTradeEntryPrefills(
      request: DcaSimulationRequestContract(
        allocations: allocations,
        amountPerContribution: amountPerContribution,
        currency: currency,
      ),
      tradeDate: DateTime.now(),
      market: market,
      noteBuilder: (allocation) => l10n.dcaSimulatorDraftNote(
        allocation.symbol,
        (amountPerContribution * allocation.weight).toString(),
        currency,
      ),
    );
    for (final prefill in prefills) {
      final recorded = await Navigator.of(context).push<bool>(
        buildAppPageRoute<bool>(
          context: context,
          pageBuilder: (_, _, _) => TradeEntryFormPage(prefill: prefill),
        ),
      );
      if (!mounted || recorded != true) return false;
    }
    return true;
  }
}

class _DcaPlansSection extends StatelessWidget {
  const _DcaPlansSection({
    required this.plans,
    required this.onExecute,
    required this.onToggle,
    required this.onDelete,
  });

  final AsyncValue<List<DcaPlan>> plans;
  final ValueChanged<DcaPlan> onExecute;
  final ValueChanged<DcaPlan> onToggle;
  final ValueChanged<DcaPlan> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return plans.when(
      loading: () => const SkeletonBox(height: 88, radius: AppRadius.lg),
      error: (error, stackTrace) => kDefaultError(context, error, stackTrace),
      data: (rows) {
        if (rows.isEmpty) {
          return SoftCard.flat(
            padding: const EdgeInsets.all(AppSpacing.s14),
            child: Text(l10n.dcaPlanEmpty, style: context.captionStyle),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.dcaPlanSectionTitle, style: context.mutedLabelStyle),
            const SizedBox(height: AppSpacing.s8),
            for (final plan in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                child: _DcaPlanCard(
                  plan: plan,
                  onExecute: () => onExecute(plan),
                  onToggle: () => onToggle(plan),
                  onDelete: () => onDelete(plan),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DcaPlanCard extends StatelessWidget {
  const _DcaPlanCard({
    required this.plan,
    required this.onExecute,
    required this.onToggle,
    required this.onDelete,
  });

  final DcaPlan plan;
  final VoidCallback onExecute;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final symbols = plan.allocations.map((item) => item.symbol).join(' · ');
    final due = MaterialLocalizations.of(
      context,
    ).formatShortDate(plan.nextDueAt.toLocal());
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(symbols, style: context.labelStyle)),
              AppBadge(
                label: plan.enabled ? l10n.dcaPlanActive : l10n.dcaPlanPaused,
                size: AppBadgeSize.compact,
                tone: plan.enabled
                    ? AppBadgeTone.success
                    : AppBadgeTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.dcaPlanNextDue(
              due,
              plan.amountPerContribution.toString(),
              plan.currency,
            ),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              FButton(
                onPress: plan.enabled ? onExecute : null,
                child: Text(l10n.dcaPlanExecuteNow),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: onToggle,
                child: Text(
                  plan.enabled ? l10n.dcaPlanPause : l10n.dcaPlanResume,
                ),
              ),
              FButton(
                variant: FButtonVariant.ghost,
                onPress: onDelete,
                child: Text(l10n.commonDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DcaControls extends StatelessWidget {
  const _DcaControls({
    required this.formKey,
    required this.symbols,
    required this.amount,
    required this.currency,
    required this.market,
    required this.frequency,
    required this.years,
    required this.busy,
    required this.onMarketChanged,
    required this.onFrequencyChanged,
    required this.onYearsChanged,
    required this.onRun,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController symbols;
  final TextEditingController amount;
  final TextEditingController currency;
  final AssetMarket market;
  final DcaFrequency frequency;
  final int years;
  final bool busy;
  final ValueChanged<AssetMarket> onMarketChanged;
  final ValueChanged<DcaFrequency> onFrequencyChanged;
  final ValueChanged<int> onYearsChanged;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTextFormField(
              control: FTextFieldControl.managed(controller: symbols),
              label: Text(l10n.dcaSimulatorSymbolField),
              hint: l10n.dcaSimulatorSymbolHint,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              validator: (value) => _parseSymbols(value ?? '').isEmpty
                  ? l10n.dcaSimulatorInvalidSymbols
                  : null,
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: FTextFormField(
                    control: FTextFieldControl.managed(controller: amount),
                    label: Text(l10n.dcaSimulatorAmountField),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    validator: (value) {
                      final parsed = Decimal.tryParse(value?.trim() ?? '');
                      if (parsed == null || parsed <= Decimal.zero) {
                        return l10n.dcaSimulatorInvalidAmount;
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: FTextFormField(
                    control: FTextFieldControl.managed(controller: currency),
                    label: Text(l10n.dcaSimulatorCurrencyField),
                    textCapitalization: TextCapitalization.characters,
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      return raw.length < 3
                          ? l10n.dcaSimulatorInvalidCurrency
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            FSelect<AssetMarket>(
              items: {
                l10n.dcaSimulatorMarketUs: AssetMarket.usStock,
                l10n.dcaSimulatorMarketHk: AssetMarket.hkStock,
                l10n.dcaSimulatorMarketCn: AssetMarket.cnA,
                l10n.dcaSimulatorMarketCrypto: AssetMarket.crypto,
              },
              control: FSelectControl<AssetMarket>.managed(
                initial: market,
                onChange: (value) {
                  if (value != null) onMarketChanged(value);
                },
              ),
              label: Text(l10n.dcaSimulatorMarketField),
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: FSelect<DcaFrequency>(
                    items: {
                      l10n.dcaSimulatorFrequencyMonthly: DcaFrequency.monthly,
                      l10n.dcaSimulatorFrequencyQuarterly:
                          DcaFrequency.quarterly,
                    },
                    control: FSelectControl<DcaFrequency>.managed(
                      initial: frequency,
                      onChange: (value) {
                        if (value != null) onFrequencyChanged(value);
                      },
                    ),
                    label: Text(l10n.dcaSimulatorFrequencyField),
                  ),
                ),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: FSelect<int>(
                    items: {
                      l10n.dcaSimulatorWindow1y: 1,
                      l10n.dcaSimulatorWindow3y: 3,
                      l10n.dcaSimulatorWindow5y: 5,
                    },
                    control: FSelectControl<int>.managed(
                      initial: years,
                      onChange: (value) {
                        if (value != null) onYearsChanged(value);
                      },
                    ),
                    label: Text(l10n.dcaSimulatorWindowField),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            FButton(
              onPress: busy ? null : onRun,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FLucideIcons.workflow, size: AppIconSizes.h18),
                  const SizedBox(width: AppSpacing.s6),
                  Text(l10n.dcaSimulatorRunAction),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DcaResults extends StatelessWidget {
  const _DcaResults({required this.state, required this.onDraft});

  final DcaSimulationState state;
  final VoidCallback onDraft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = state.result;
    if (result.isEmpty) return _ErrorState(message: l10n.dcaSimulatorEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard.flat(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.dcaSimulatorResultTitle,
                      style: context.rowTitleStyle,
                    ),
                  ),
                  _FreshnessChip(freshness: state.freshness),
                ],
              ),
              const SizedBox(height: AppSpacing.s14),
              _MetricGrid(result: result),
              const SizedBox(height: AppSpacing.s20),
              Text(l10n.dcaSimulatorChartTitle, style: context.labelStyle),
              const SizedBox(height: AppSpacing.s10),
              SizedBox(
                height: AppChartHeights.full,
                child: NwLineChart(
                  series: [
                    ChartSeries(
                      name: l10n.dcaSimulatorChartSeries,
                      points: [
                        for (final point in result.equityCurve)
                          ChartPoint(
                            x: point.asOf.millisecondsSinceEpoch.toDouble(),
                            y: point.value.toDouble(),
                          ),
                      ],
                    ),
                  ],
                  xAxis: const TimeAxis(
                    format: AxisDateFormat.monthYear,
                    maxLabels: 5,
                  ),
                  yAxis: ValueAxis.currency(
                    currencyCode: result.currency,
                    maxLabels: 4,
                  ),
                  interpolation: ChartInterpolation.linear,
                  semanticLabel: l10n.dcaSimulatorChartTitle,
                ),
              ),
              const SizedBox(height: AppSpacing.s14),
              for (final position in result.positions)
                _PositionRow(position: position, currency: result.currency),
              const SizedBox(height: AppSpacing.s12),
              SizedBox(
                width: double.infinity,
                child: FButton(
                  variant: FButtonVariant.secondary,
                  onPress: onDraft,
                  child: Text(l10n.dcaSimulatorDraftAction),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.result});

  final DcaSimulationResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    return Wrap(
      spacing: AppSpacing.s10,
      runSpacing: AppSpacing.s10,
      children: [
        _MoneyMetric(
          label: l10n.dcaSimulatorTotalInvested,
          amount: result.totalInvested,
          currency: result.currency,
        ),
        _MoneyMetric(
          label: l10n.dcaSimulatorEndingValue,
          amount: result.endingValue,
          currency: result.currency,
        ),
        _TextMetric(
          label: l10n.dcaSimulatorCumulativeReturn,
          value: formatters.percent(
            result.cumulativeReturn.toDouble(),
            decimalDigits: 1,
          ),
        ),
        _MoneyMetric(
          label: l10n.dcaSimulatorAverageCost,
          amount: result.averageCost,
          currency: result.currency,
        ),
        _TextMetric(
          label: l10n.dcaSimulatorMaxDrawdown,
          value: formatters.percent(
            result.maxDrawdown.toDouble(),
            decimalDigits: 1,
          ),
        ),
      ],
    );
  }
}

class _MoneyMetric extends StatelessWidget {
  const _MoneyMetric({
    required this.label,
    required this.amount,
    required this.currency,
  });

  final String label;
  final Decimal amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return _MetricShell(
      label: label,
      child: AnimatedMoneyText(
        amount: amount.toDouble(),
        currencyCode: currency,
        style: TypographyTokens.numericBodyStrong,
      ),
    );
  }
}

class _TextMetric extends StatelessWidget {
  const _TextMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _MetricShell(
      label: label,
      child: Text(value, style: TypographyTokens.numericBodyStrong),
    );
  }
}

class _MetricShell extends StatelessWidget {
  const _MetricShell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppControlWidths.metricTile,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.theme.colors.foreground.withValues(
            alpha: AppOpacity.whisper,
          ),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.captionStyle),
              const SizedBox(height: AppSpacing.s4),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow({required this.position, required this.currency});

  final DcaPositionResult position;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        children: [
          Expanded(child: Text(position.symbol, style: context.labelStyle)),
          Flexible(
            child: Text(
              l10n.dcaSimulatorPositionAverageCost(
                currency,
                formatters.currency(position.averageCost, code: currency),
              ),
              style: context.captionStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FreshnessChip extends StatelessWidget {
  const _FreshnessChip({required this.freshness});

  final DataFreshness freshness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (freshness) {
      DataFreshness.live => l10n.dcaSimulatorFreshnessLive,
      DataFreshness.cachedFresh => l10n.dcaSimulatorFreshnessCache,
      DataFreshness.stale => l10n.dcaSimulatorFreshnessStale,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.foreground.withValues(
          alpha: AppOpacity.whisper,
        ),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s6,
        ),
        child: Text(label, style: context.theme.typography.body.xs),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState.error(title: message);
  }
}

List<String> _parseSymbols(String raw) => [
  for (final allocation in _parseAllocations(raw)) allocation.symbol,
];

List<DcaAllocation> _parseAllocations(String raw) {
  final tokens = raw
      .split(RegExp(r'[,，\s]+'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) return const [];
  final weighted = <({String symbol, Decimal? weight})>[];
  for (final token in tokens) {
    final parts = token.split(':');
    final symbol = parts.first.trim().toUpperCase();
    if (symbol.isEmpty) continue;
    var weight = parts.length == 1 ? null : Decimal.tryParse(parts.last.trim());
    if (weight != null && weight > Decimal.one) {
      weight = (weight / Decimal.fromInt(100)).toDecimal(
        scaleOnInfinitePrecision: 16,
      );
    }
    if (weight != null && weight <= Decimal.zero) return const [];
    weighted.add((symbol: symbol, weight: weight));
  }
  if (weighted.isEmpty) return const [];
  final fallback = (Decimal.one / Decimal.fromInt(weighted.length)).toDecimal(
    scaleOnInfinitePrecision: 16,
  );
  final rawWeights = [for (final item in weighted) item.weight ?? fallback];
  final total = rawWeights.fold(Decimal.zero, (sum, weight) => sum + weight);
  if (total <= Decimal.zero) return const [];
  return [
    for (var i = 0; i < weighted.length; i++)
      DcaAllocation(
        symbol: weighted[i].symbol,
        weight: (rawWeights[i] / total).toDecimal(scaleOnInfinitePrecision: 16),
      ),
  ];
}
