import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../domain/services/market_data_service.dart';
import '../../../domain/values/asset_market.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/dca_simulation_service.dart';
import '../application/dca_trade_entry_prefills.dart';
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
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.dcaSimulatorTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: RefreshIndicator(
        onRefresh: () => ref.read(dcaSimulationProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(Breakpoints.isMobile(MediaQuery.sizeOf(context).width) ? AppSpacing.s16 : AppSpacing.s24,
            AppSpacing.s8,
            Breakpoints.isMobile(MediaQuery.sizeOf(context).width) ? AppSpacing.s16 : AppSpacing.s24,
            80 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
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
              error: (error, _) =>
                  _ErrorState(message: l10n.dcaSimulatorLoadError('$error')),
              data: (data) =>
                  _DcaResults(state: data, onDraft: () => _draftTrades(data)),
            ),
          ],
        ),
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

  Future<void> _draftTrades(DcaSimulationState state) async {
    final l10n = AppLocalizations.of(context);
    final symbols = state.request.symbols;
    if (symbols.isEmpty) return;
    final weight = (Decimal.one / Decimal.fromInt(symbols.length)).toDecimal(
      scaleOnInfinitePrecision: 16,
    );
    final prefills = buildDcaTradeEntryPrefills(
      request: DcaSimulationRequestContract(
        allocations: [
          for (final symbol in symbols)
            DcaAllocation(symbol: symbol, weight: weight),
        ],
        amountPerContribution: state.request.amountPerContribution,
        currency: state.request.currency,
      ),
      tradeDate: DateTime.now(),
      noteBuilder: (allocation) => l10n.dcaSimulatorDraftNote(
        allocation.symbol,
        (state.request.amountPerContribution * allocation.weight).toString(),
        state.request.currency,
      ),
    );
    for (final prefill in prefills) {
      final recorded = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => TradeEntryFormPage(prefill: prefill)),
      );
      if (!mounted || recorded != true) return;
    }
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
    return SoftCard(
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
        SoftCard(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.dcaSimulatorResultTitle,
                      style: context.theme.typography.lg,
                    ),
                  ),
                  _FreshnessChip(freshness: state.freshness),
                ],
              ),
              const SizedBox(height: AppSpacing.s14),
              _MetricGrid(result: result),
              const SizedBox(height: AppSpacing.s20),
              Text(
                l10n.dcaSimulatorChartTitle,
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.s10),
              SizedBox(
                height: 220,
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
    return Wrap(
      spacing: 10,
      runSpacing: 10,
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
          value: _formatPercent(result.cumulativeReturn),
        ),
        _MoneyMetric(
          label: l10n.dcaSimulatorAverageCost,
          amount: result.averageCost,
          currency: result.currency,
        ),
        _TextMetric(
          label: l10n.dcaSimulatorMaxDrawdown,
          value: _formatPercent(result.maxDrawdown),
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
        style: TypographyTokens.numericBody.copyWith(
          fontWeight: FontWeight.w700,
        ),
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
      child: Text(
        value,
        style: TypographyTokens.numericBody.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
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
      width: 148,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.theme.colors.foreground.withValues(alpha: AppOpacity.whisper),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              position.symbol,
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            l10n.dcaSimulatorPositionAverageCost(
              currency,
              position.averageCost.toString(),
            ),
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
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
        color: context.theme.colors.foreground.withValues(alpha: AppOpacity.whisper),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
        child: Text(label, style: context.theme.typography.xs),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: context.theme.typography.sm,
        ),
      ),
    );
  }
}

List<String> _parseSymbols(String raw) => [
  for (final token in raw.split(RegExp(r'[,，\\s]+')))
    if (token.trim().isNotEmpty) token.trim().toUpperCase(),
];

String _formatPercent(Decimal ratio) {
  final value = ratio.toDouble() * 100;
  return '${value.toStringAsFixed(1)}%';
}
