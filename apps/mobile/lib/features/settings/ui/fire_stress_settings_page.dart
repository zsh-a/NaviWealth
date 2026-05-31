/// Advanced sub-page for tuning the FIRE stress-test parameters.
///
/// Until this page existed, `FireRiskSettings` was an orphan: persisted
/// through `firePlanExtrasProvider`, JSON-encoded, consumed by the
/// stress-test engine — yet nowhere in the UI could the user actually
/// change its four knobs. The FIRE stress card shipped showing
/// "drawdown 35% · expense +20% · fx 10%" without ever letting the
/// user say "actually, plan for a 50% drawdown instead."
///
/// We slot it next to the concentration-thresholds page (both are
/// "advanced" knobs reached via link rows from Investment Preferences)
/// so the discoverability problem stays solved.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../fire/data/fire_plan_preferences.dart';
import '../../fire/data/fire_providers.dart';
import '../../fire/domain/fire_plan.dart';

class FireStressSettingsPage extends ConsumerWidget {
  const FireStressSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.settingsStressTestTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padding = Breakpoints.isMobile(constraints.maxWidth)
              ? const EdgeInsets.all(AppSpacing.s16)
              : const EdgeInsets.all(AppSpacing.s24);
          return ListView(
            padding: padding,
            children: const [
              _Hint(),
              SizedBox(height: AppSpacing.s12),
              SoftCard(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
                child: FireStressSettings(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      child: Text(
        l10n.settingsStressTestHint,
        style: context.theme.typography.xs.copyWith(
          color: context.theme.colors.mutedForeground,
          height: 1.45,
        ),
      ),
    );
  }
}

/// The four-knob panel. Exposed (not file-private) so it can be unit
/// tested or embedded elsewhere if needed.
class FireStressSettings extends ConsumerWidget {
  const FireStressSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final extras = ref.watch(firePlanExtrasProvider);
    final risk = extras.riskSettings;
    final baseCurrency = ref.watch(firePlanProvider).baseCurrency;

    void update(FireRiskSettings next) {
      ref
          .read(firePlanExtrasProvider.notifier)
          .save(extras.copyWith(riskSettings: next));
    }

    return Column(
      children: [
        _PercentSlider(
          label: l10n.settingsStressTestMarketDrawdownLabel,
          subtitle: l10n.settingsStressTestMarketDrawdownSubtitle,
          value: risk.marketDrawdownPct,
          max: 0.60,
          onChanged: (v) => update(risk.copyWith(marketDrawdownPct: v)),
        ),
        _Divider(),
        _PercentSlider(
          label: l10n.settingsStressTestExpenseShockLabel,
          subtitle: l10n.settingsStressTestExpenseShockSubtitle,
          value: risk.expenseShockPct,
          max: 0.50,
          onChanged: (v) => update(risk.copyWith(expenseShockPct: v)),
        ),
        _Divider(),
        _PercentSlider(
          label: l10n.settingsStressTestFxShockLabel,
          subtitle: l10n.settingsStressTestFxShockSubtitle,
          value: risk.fxShockPct,
          max: 0.30,
          onChanged: (v) => update(risk.copyWith(fxShockPct: v)),
        ),
        _Divider(),
        _LumpSumField(
          value: risk.oneOffShockAmount,
          baseCurrency: baseCurrency,
          onChanged: (v) => update(risk.copyWith(oneOffShockAmount: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.s14, AppSpacing.s4, AppSpacing.s14, AppSpacing.s8),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FTappable(
              onPress: () => update(const FireRiskSettings()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6, vertical: AppSpacing.s4),
                child: Text(
                  l10n.settingsStressTestResetDefaults,
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14),
      child: Container(
        height: 1,
        color: context.theme.colors.foreground.withValues(alpha: AppOpacity.whisper),
      ),
    );
  }
}

/// Slider for a percentage parameter in [0, max], rendered with a
/// trailing percent badge so the user always sees the magnitude
/// without having to drag and read the tooltip.
class _PercentSlider extends StatefulWidget {
  const _PercentSlider({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  State<_PercentSlider> createState() => _PercentSliderState();
}

class _PercentSliderState extends State<_PercentSlider> {
  late FContinuousSliderController _controller;
  bool _suppress = false;

  @override
  void initState() {
    super.initState();
    _controller = FContinuousSliderController(
      value: FSliderValue(max: _toFraction(widget.value)),
    )..addListener(_onSliderChanged);
  }

  @override
  void didUpdateWidget(covariant _PercentSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value && widget.max == oldWidget.max) return;
    final next = _toFraction(widget.value);
    if ((next - _controller.value.max).abs() < 0.0001) return;
    _suppress = true;
    try {
      _controller.value = FSliderValue(max: next);
    } finally {
      Future.microtask(() => _suppress = false);
    }
  }

  void _onSliderChanged() {
    if (_suppress) return;
    final next = _controller.value.max * widget.max;
    if ((next - widget.value).abs() < 0.0001) return;
    Future.microtask(() {
      if (!mounted) return;
      widget.onChanged(next);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onSliderChanged);
    _controller.dispose();
    super.dispose();
  }

  double _toFraction(double v) => (v / widget.max).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s14, AppSpacing.s10, AppSpacing.s14, AppSpacing.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label, style: context.theme.typography.sm),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      widget.subtitle,
                      style: context.theme.typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                '${(widget.value * 100).round()}%',
                style: context.theme.typography.sm.copyWith(
                  color: colors.mutedForeground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          FSlider(
            control: FSliderControl.managedContinuous(controller: _controller),
            tooltipBuilder: (_, v) =>
                Text('${(v * widget.max * 100).round()}%'),
          ),
        ],
      ),
    );
  }
}

/// Free-form numeric input for the lump-sum outlay (in major units of
/// the plan's base currency). Slider doesn't fit — the magnitude can
/// be anywhere from 0 to "every penny I have"; a text field with
/// commit-on-blur keeps the discoverability + precision both intact.
class _LumpSumField extends StatefulWidget {
  const _LumpSumField({
    required this.value,
    required this.baseCurrency,
    required this.onChanged,
  });

  final double value;
  final String baseCurrency;
  final ValueChanged<double> onChanged;

  @override
  State<_LumpSumField> createState() => _LumpSumFieldState();
}

class _LumpSumFieldState extends State<_LumpSumField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _LumpSumField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focusNode.hasFocus) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) return;
    final parsed = Decimal.tryParse(_controller.text.trim());
    final next = parsed?.toDouble() ?? 0;
    if ((next - widget.value).abs() < 0.001) {
      // Re-format so trailing zeros / weird whitespace are normalised.
      _controller.text = _format(widget.value);
      return;
    }
    widget.onChanged(next);
  }

  static String _format(double v) {
    if (v == 0) return '0';
    // Strip trailing `.0` for whole numbers; otherwise preserve as-is.
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s14, AppSpacing.s10, AppSpacing.s14, AppSpacing.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsStressTestLumpSumLabel,
            style: context.theme.typography.sm,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            l10n.settingsStressTestLumpSumSubtitle,
            style: context.theme.typography.xs.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Row(
            children: [
              Expanded(
                child: FTextField(
                  control: FTextFieldControl.managed(controller: _controller),
                  focusNode: _focusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  hint: l10n.settingsStressTestLumpSumHint,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                widget.baseCurrency,
                style: context.theme.typography.sm.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
