import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/config/app_version.dart';
import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../analytics/data/risk_threshold_preferences.dart';
import '../../shared/forms/currency_picker.dart';
import '../data/base_currency_preference.dart';
import 'inline_setting_row.dart';

/// Settings landing page — iOS-style inset-grouped sections.
///
/// Every selector is a single-line [InlineSettingRow] (icon + label +
/// trailing value chip), giving the page roughly half the vertical
/// footprint of the legacy stacked `FSelect` layout while keeping every
/// option discoverable. Tap any row to open a dedicated picker sheet.
class SettingsOverview extends ConsumerWidget {
  const SettingsOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return ListView(
      padding: const EdgeInsets.all(16).copyWith(
        bottom:
            const EdgeInsets.all(16).bottom +
            64 +
            MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const _AccountHeader(),
        const SizedBox(height: 16),
        _SectionHeader(title: l10n.settingsAccountSection),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _AccountSection(),
            ],
          ),
        ),
        _SectionHeader(title: l10n.settingsAppearanceSection),
        const SoftCard(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: _AppearanceSection(),
        ),
        _SectionHeader(title: l10n.settingsRiskSection),
        const SoftCard(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: _RiskThresholdSettings(),
        ),
        _SectionHeader(title: l10n.settingsDataSection),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              InlineLinkRow(
                icon: Icons.cloud_sync_outlined,
                label: l10n.settingsSyncTitle,
                subtitle: l10n.settingsSyncSubtitle,
                onTap: () => context.goNamed(AppRouteNames.sync),
              ),
              _SectionDivider(),
              InlineLinkRow(
                icon: Icons.backup_outlined,
                label: l10n.settingsDataTitle,
                subtitle: l10n.settingsDataSubtitle,
                onTap: () => context.goNamed(AppRouteNames.backup),
              ),
              _SectionDivider(),
              InlineLinkRow(
                icon: Icons.visibility_outlined,
                label: 'AI 透明度',
                subtitle: '查看最近 AI 调用的详细轨迹',
                onTap: () => context.goNamed(AppRouteNames.aiTransparency),
              ),
            ],
          ),
        ),
        if (kDebugMode) ...[
          _SectionHeader(title: l10n.settingsDeveloperSection),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: InlineLinkRow(
              icon: Icons.bug_report_outlined,
              label: l10n.settingsLogsTitle,
              subtitle: l10n.settingsLogsSubtitle,
              onTap: () => context.goNamed(AppRouteNames.logs),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const SoftCard(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: _AboutTile(),
        ),
      ],
    );
  }
}

/// iOS-style inset-grouped section header — small, all-caps, muted.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
      child: Text(
        title.toUpperCase(),
        style: context.theme.typography.xs2.copyWith(
          color: context.theme.colors.mutedForeground,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Single-pixel divider between adjacent rows in the same SoftCard
/// section. Matches the divider used elsewhere (alpha 0.05) so the
/// rows feel ribbon-grouped rather than card-stacked.
class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        height: 1,
        color: context.theme.colors.foreground.withValues(alpha: 0.05),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              // Soft teal disc — matches the icon affordance used in
              // SoftCard rows / AccountCategoryPicker so the avatar
              // reads as part of the same visual family rather than a
              // Material primaryContainer one-off.
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.account_circle_outlined,
              color: colors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsAccountTitle,
                  style: context.theme.typography.xl,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.settingsAccountSubtitle,
                  style: context.theme.typography.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);

    return Column(
      children: [
        InlineLinkRow(
          icon: Icons.devices_outlined,
          label: l10n.settingsDevicesTitle,
          subtitle: l10n.settingsDevicesSubtitle,
          onTap: () => context.goNamed(AppRouteNames.devices),
        ),
        _SectionDivider(),
        InlineSettingRow<String>(
          icon: Icons.currency_exchange,
          label: l10n.settingsBaseCurrencyTitle,
          value: baseCurrency,
          options: {
            for (final code in kCommonCurrencies)
              currencyDisplayLabel(l10n, code): code,
          },
          onChanged: (picked) =>
              ref.read(baseCurrencyProvider.notifier).set(picked),
        ),
        _SectionDivider(),
        InlineLinkRow(
          icon: Icons.published_with_changes_outlined,
          label: l10n.settingsFxRatesTitle,
          subtitle: l10n.settingsFxRatesSubtitle,
          onTap: () => context.goNamed(AppRouteNames.fxRates),
        ),
      ],
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final marketMode = ref.watch(marketColorModeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final compact = ref.watch(compactDensityProvider);

    return Column(
      children: [
        InlineSettingRow<ThemeMode>(
          icon: Icons.brightness_6_outlined,
          label: l10n.settingsThemeModeTitle,
          value: themeMode,
          options: {
            for (final m in ThemeMode.values) _themeModeLabel(l10n, m): m,
          },
          onChanged: (m) {
            Haptics.selection();
            ref.read(themeModeProvider.notifier).set(m);
          },
        ),
        _SectionDivider(),
        InlineSettingRow<MarketColorMode>(
          icon: Icons.swap_vert,
          label: l10n.settingsMarketColorTitle,
          value: marketMode,
          options: {
            for (final m in MarketColorMode.values)
              _marketModeLabel(l10n, m): m,
          },
          onChanged: (m) =>
              ref.read(marketColorModeProvider.notifier).set(m),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: _MarketColorPreview(),
        ),
        _SectionDivider(),
        InlineSwitchRow(
          icon: Icons.density_medium_outlined,
          label: l10n.settingsCompactDensityTitle,
          subtitle: l10n.settingsCompactDensitySubtitle,
          value: compact,
          onChanged: (next) =>
              ref.read(compactDensityProvider.notifier).set(next),
        ),
        _SectionDivider(),
        InlineSettingRow<String>(
          icon: Icons.translate_outlined,
          label: l10n.settingsLanguageTitle,
          value: locale?.languageCode ?? '',
          options: {
            l10n.langSystem: '',
            l10n.langEnglish: 'en',
            l10n.langChinese: 'zh',
          },
          onChanged: (picked) {
            Haptics.selection();
            ref
                .read(localeProvider.notifier)
                .set(picked.isEmpty ? null : Locale(picked));
          },
        ),
      ],
    );
  }

  String _themeModeLabel(AppLocalizations l10n, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.system => l10n.themeModeSystem,
        ThemeMode.light => l10n.themeModeLight,
        ThemeMode.dark => l10n.themeModeDark,
      };

  String _marketModeLabel(AppLocalizations l10n, MarketColorMode mode) =>
      switch (mode) {
        MarketColorMode.redUpGreenDown => l10n.marketColorRedUpGreenDown,
        MarketColorMode.greenUpRedDown => l10n.marketColorGreenUpRedDown,
        MarketColorMode.colorblind => l10n.marketColorColorblind,
      };
}

class _AboutTile extends ConsumerWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final versionAsync = ref.watch(appVersionProvider);
    final colors = context.theme.colors;
    final subtitle = versionAsync.when(
      loading: () => l10n.settingsAboutSubtitle('…'),
      error: (_, _) => l10n.settingsAboutSubtitle('?'),
      data: (info) {
        final base = l10n.settingsAboutSubtitle(
          '${info.version}+${info.buildNumber}',
        );
        if (info.commitSha == 'dev' || info.commitSha.isEmpty) return base;
        final shortSha = info.commitSha.length >= 7
            ? info.commitSha.substring(0, 7)
            : info.commitSha;
        return '$base · $shortSha';
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.mutedForeground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.settingsAboutTitle, style: context.theme.typography.sm),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.theme.typography.xs.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketColorPreview extends StatelessWidget {
  const _MarketColorPreview();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        DeltaChip(value: 1.23, format: DeltaFormat.percent),
        DeltaChip(value: -0.42, format: DeltaFormat.percent),
        DeltaChip(value: 0, format: DeltaFormat.percent),
      ],
    );
  }
}

class _RiskThresholdSettings extends ConsumerWidget {
  const _RiskThresholdSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final thresholds = ref.watch(concentrationThresholdsProvider);

    return Column(
      children: [
        _ThresholdSlider(
          icon: Icons.account_balance_wallet_outlined,
          label: l10n.settingsRiskAssetLabel,
          value: thresholds.assetWarning,
          onChanged: (v) =>
              ref.read(concentrationThresholdsProvider.notifier).updateAsset(v),
        ),
        _SectionDivider(),
        _ThresholdSlider(
          icon: Icons.category_outlined,
          label: l10n.settingsRiskSectorLabel,
          value: thresholds.sectorWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateSector(v),
        ),
        _SectionDivider(),
        _ThresholdSlider(
          icon: Icons.public,
          label: l10n.settingsRiskRegionLabel,
          value: thresholds.regionWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateRegion(v),
        ),
        _SectionDivider(),
        _ThresholdSlider(
          icon: Icons.currency_exchange,
          label: l10n.settingsRiskCurrencyLabel,
          value: thresholds.currencyWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateCurrency(v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FTappable(
              onPress: () => ref
                  .read(concentrationThresholdsProvider.notifier)
                  .resetToDefaults(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                child: Text(
                  l10n.settingsRiskResetDefaults,
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
    // Push the new external value into the controller without
    // re-invoking onChanged — otherwise we'd loop back into the parent
    // notifier from inside a layout pass.
    _suppressOnChange = true;
    try {
      _controller.value = FSliderValue(max: next);
    } finally {
      // Reset on the next microtask so the legitimate user-driven
      // notification immediately after still fires.
      Future.microtask(() => _suppressOnChange = false);
    }
  }

  void _onSliderChanged() {
    if (_suppressOnChange) return;
    final next = 0.05 + _controller.value.max * 0.90;
    if ((next - widget.value).abs() < 0.0001) return;
    // Defer the parent notifier write to a microtask. FSliderController
    // sometimes notifies during layout (attach/didUpdateWidget); pushing
    // out of the layout phase keeps the StateNotifier guard happy.
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(widget.icon, size: 18, color: colors.mutedForeground),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(
              widget.label,
              style: context.theme.typography.sm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: FSlider(
              control: FSliderControl.managedContinuous(controller: _controller),
              tooltipBuilder: (_, v) =>
                  Text('${((0.05 + v * 0.90) * 100).round()}%'),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${(widget.value * 100).round()}%',
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
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
