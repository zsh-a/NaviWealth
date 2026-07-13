/// Advanced sub-page that exposes the four concentration-alert
/// thresholds (asset / sector / region / currency).
///
/// Previously, this was the entire "Risk" section on the Settings
/// overview — four sliders consuming a whole card for a power-user
/// setting most people will never touch. The new SSOT model promotes
/// the actual user-facing "Risk appetite" dial to the top of Settings;
/// these thresholds live behind a link row labelled "Advanced". Users
/// who don't open the link get reasonable defaults driven by their
/// appetite; users who do open it can override any of the four
/// thresholds and reset to defaults at any time.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/analytics/data/risk_threshold_preferences.dart';

import '../../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

class RiskThresholdsPage extends ConsumerWidget {
  const RiskThresholdsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.settingsRiskThresholdsTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          SettingsHintText(l10n.settingsRiskThresholdsHint),
          const SizedBox(height: AppSpacing.s12),
          const SoftCard.raised(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: RiskThresholdSettings(),
          ),
        ],
      ),
    );
  }
}

/// The four-slider concentration threshold panel.
///
/// Lives in this file so the [RiskThresholdsPage] is the canonical
/// host. Exposed (rather than file-private) because tests and the
/// settings overview link row both want to deep-link to it.
class RiskThresholdSettings extends ConsumerWidget {
  const RiskThresholdSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final thresholds = ref.watch(concentrationThresholdsProvider);

    return Column(
      children: [
        _ThresholdSlider(
          icon: FLucideIcons.wallet,
          label: l10n.settingsRiskAssetLabel,
          value: thresholds.assetWarning,
          onChanged: (v) =>
              ref.read(concentrationThresholdsProvider.notifier).updateAsset(v),
        ),
        const AppGradientDivider(),
        _ThresholdSlider(
          icon: FLucideIcons.layoutGrid,
          label: l10n.settingsRiskSectorLabel,
          value: thresholds.sectorWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateSector(v),
        ),
        const AppGradientDivider(),
        _ThresholdSlider(
          icon: FLucideIcons.globe,
          label: l10n.settingsRiskRegionLabel,
          value: thresholds.regionWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateRegion(v),
        ),
        const AppGradientDivider(),
        _ThresholdSlider(
          icon: FLucideIcons.arrowLeftRight,
          label: l10n.settingsRiskCurrencyLabel,
          value: thresholds.currencyWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateCurrency(v),
        ),
        SettingsFooterAction(
          icon: FLucideIcons.rotateCcw,
          label: l10n.settingsRiskResetDefaults,
          onPress: () => ref
              .read(concentrationThresholdsProvider.notifier)
              .resetToDefaults(),
        ),
      ],
    );
  }
}

/// Compact slider row — icon + label · slider · trailing percent.
///
/// Owns its own [FContinuousSliderController] across rebuilds so a
/// LayoutBuilder rebuild (e.g. window resize) doesn't make Forui call
/// `attach` and synchronously fire `onChange` during the layout pass —
/// which would crash with `StateNotifier.state= called during build`
/// when the callback writes back into a Riverpod controller.
///
/// External `value` updates (e.g. from "Reset to defaults") are
/// applied through `didUpdateWidget` only when they actually differ
/// from the controller's current value.
class _ThresholdSlider extends StatefulWidget {
  const _ThresholdSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_ThresholdSlider> createState() => _ThresholdSliderState();
}

class _ThresholdSliderState extends State<_ThresholdSlider> {
  late FContinuousSliderController _controller;
  bool _suppressOnChange = false;

  @override
  void initState() {
    super.initState();
    _controller = FContinuousSliderController(
      value: FSliderValue(max: _toFraction(widget.value)),
    )..addListener(_onSliderChanged);
  }

  @override
  void didUpdateWidget(covariant _ThresholdSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;
    final next = _toFraction(widget.value);
    if ((next - _controller.value.max).abs() < 0.0001) return;
    _suppressOnChange = true;
    try {
      _controller.value = FSliderValue(max: next);
    } finally {
      Future.microtask(() => _suppressOnChange = false);
    }
  }

  void _onSliderChanged() {
    if (_suppressOnChange) return;
    final next = 0.05 + _controller.value.max * 0.90;
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

  double _toFraction(double v) => ((v - 0.05) / 0.90).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        children: [
          Icon(
            widget.icon,
            size: AppIconSizes.h18,
            color: colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s12),
          SizedBox(
            width: AppControlWidths.settingsShortLabel,
            child: Text(
              widget.label,
              style: context.theme.typography.body.sm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: FSlider(
              control: FSliderControl.managedContinuous(
                controller: _controller,
              ),
              tooltipBuilder: (_, v) =>
                  Text('${((0.05 + v * 0.90) * 100).round()}%'),
            ),
          ),
          SizedBox(
            width: AppControlWidths.settingsShortValue,
            child: Text(
              '${(widget.value * 100).round()}%',
              style: context.bodyCaptionStyle.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
