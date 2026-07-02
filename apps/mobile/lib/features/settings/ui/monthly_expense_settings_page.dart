/// Editor for the monthly-expense model that powers the FIRE
/// projection.
///
/// `MonthlyExpensePreferencesController` has lived in
/// `features/expense/data/expense_report_providers.dart` since the FIRE
/// projection first needed a "what monthly spend should I plan for?"
/// signal. The setter API (`setWindow` / `setOverride` / `useAuto`)
/// was always there — there just was no UI calling it. This page is
/// that UI: a window-size slider plus an optional manual override,
/// reachable from the Investment Preferences card in Settings.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../expense/data/expense_report_providers.dart';
import '../../home/data/dashboard_providers.dart';

class MonthlyExpenseSettingsPage extends ConsumerWidget {
  const MonthlyExpenseSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.settingsMonthlyExpenseLabel,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          SettingsHintText(l10n.settingsMonthlyExpenseHint),
          const SizedBox(height: AppSpacing.s12),
          const SoftCard(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: MonthlyExpenseSettings(),
          ),
        ],
      ),
    );
  }
}

class MonthlyExpenseSettings extends ConsumerWidget {
  const MonthlyExpenseSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(monthlyExpensePreferencesProvider);
    final controller = ref.read(monthlyExpensePreferencesProvider.notifier);
    final baseCurrency = ref.watch(dashboardBaseCurrencyProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WindowSlider(
          windowMonths: prefs.windowMonths,
          onChanged: controller.setWindow,
        ),
        const AppGradientDivider(),
        _OverrideField(
          value: prefs.override,
          baseCurrency: baseCurrency,
          onChanged: controller.setOverride,
        ),
        SettingsFooterAction(
          icon: FLucideIcons.rotateCcw,
          label: l10n.settingsMonthlyExpenseResetDefaults,
          onPress: () {
            controller.useAuto();
            controller.setWindow(
              MonthlyExpensePreferencesController.defaultWindow,
            );
          },
        ),
      ],
    );
  }
}

class _WindowSlider extends StatefulWidget {
  const _WindowSlider({required this.windowMonths, required this.onChanged});

  final int windowMonths;
  final ValueChanged<int> onChanged;

  @override
  State<_WindowSlider> createState() => _WindowSliderState();
}

class _WindowSliderState extends State<_WindowSlider> {
  static const int _min = MonthlyExpensePreferencesController.minWindow;
  static const int _max = MonthlyExpensePreferencesController.maxWindow;

  late FContinuousSliderController _controller;
  bool _suppress = false;

  @override
  void initState() {
    super.initState();
    _controller = FContinuousSliderController(
      value: FSliderValue(max: _toFraction(widget.windowMonths)),
    )..addListener(_onSliderChanged);
  }

  @override
  void didUpdateWidget(covariant _WindowSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.windowMonths == oldWidget.windowMonths) return;
    final next = _toFraction(widget.windowMonths);
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
    final months = (_min + _controller.value.max * (_max - _min)).round();
    if (months == widget.windowMonths) return;
    Future.microtask(() {
      if (!mounted) return;
      widget.onChanged(months);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onSliderChanged);
    _controller.dispose();
    super.dispose();
  }

  double _toFraction(int months) =>
      ((months - _min) / (_max - _min)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s14,
        AppSpacing.s10,
        AppSpacing.s14,
        AppSpacing.s10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsMonthlyExpenseWindowLabel,
                      style: context.theme.typography.body.sm,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      l10n.settingsMonthlyExpenseWindowSubtitle,
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                l10n.settingsMonthlyExpenseWindowValue(widget.windowMonths),
                style: context.bodyCaptionStyle.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          FSlider(
            control: FSliderControl.managedContinuous(controller: _controller),
            tooltipBuilder: (_, v) {
              final months = (_min + v * (_max - _min)).round();
              return Text(l10n.settingsMonthlyExpenseWindowValue(months));
            },
          ),
        ],
      ),
    );
  }
}

class _OverrideField extends StatefulWidget {
  const _OverrideField({
    required this.value,
    required this.baseCurrency,
    required this.onChanged,
  });

  /// The current manual override, or `null` when the auto-derivation
  /// is in effect. Naming the field `value` (not `override`) avoids
  /// shadowing Dart's `@override` annotation on this widget.
  final Decimal? value;
  final String baseCurrency;
  final ValueChanged<Decimal?> onChanged;

  @override
  State<_OverrideField> createState() => _OverrideFieldState();
}

class _OverrideFieldState extends State<_OverrideField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _OverrideField oldWidget) {
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
    final text = _controller.text.trim();
    if (text.isEmpty) {
      if (widget.value != null) widget.onChanged(null);
      return;
    }
    final parsed = Decimal.tryParse(text);
    if (parsed == null || parsed <= Decimal.zero) {
      // Reject negatives / garbage by reverting the display.
      _controller.text = _format(widget.value);
      return;
    }
    if (widget.value == parsed) return;
    widget.onChanged(parsed);
  }

  static String _format(Decimal? v) => v == null ? '' : v.toString();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s14,
        AppSpacing.s10,
        AppSpacing.s14,
        AppSpacing.s10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsMonthlyExpenseOverrideLabel,
            style: context.theme.typography.body.sm,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            l10n.settingsMonthlyExpenseOverrideSubtitle,
            style: context.captionStyle,
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
                  hint: l10n.settingsMonthlyExpenseOverrideHint,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(widget.baseCurrency, style: context.bodyCaptionStyle),
            ],
          ),
        ],
      ),
    );
  }
}
