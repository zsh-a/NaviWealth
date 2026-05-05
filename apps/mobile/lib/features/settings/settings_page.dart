import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_version.dart';
import '../../core/haptics/haptics.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../analytics/data/risk_threshold_preferences.dart';
import '../shared/forms/currency_picker.dart';
import 'data/base_currency_preference.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final marketMode = ref.watch(marketColorModeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final baseCurrency = ref.watch(baseCurrencyProvider);

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.settingsAppBarTitle),
        actions: const [],
      ),
      body: ListView(
        padding: Spacing.pageMobile.copyWith(
          bottom: Spacing.pageMobile.bottom +
              Spacing.floatingBarClearance +
              MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          // ── Account ──
          LiquidGlassCard(
            layer: GlassLayer.tertiary,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(l10n.settingsAccountTitle),
                  subtitle: Text(l10n.settingsAccountSubtitle),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: Text(l10n.settingsDevicesTitle),
                  subtitle: Text(l10n.settingsDevicesSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed('devices'),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.s16,
                    vertical: Spacing.s8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.currency_exchange),
                      const SizedBox(width: Spacing.s16),
                      Expanded(
                        child: AppDropdown<String>(
                          value: baseCurrency,
                          label: l10n.settingsBaseCurrencyTitle,
                          displayBuilder: (_, v) =>
                              Text(v ?? '', style: Theme.of(context).textTheme.bodyMedium),
                          items: [
                            for (final code in kCommonCurrencies)
                              DropdownMenuItem(
                                value: code,
                                child: Text(currencyDisplayLabel(l10n, code)),
                              ),
                          ],
                          onChanged: (picked) async {
                            if (picked != null && picked != baseCurrency) {
                              await ref
                                  .read(baseCurrencyProvider.notifier)
                                  .set(picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.published_with_changes_outlined),
                  title: Text(l10n.settingsFxRatesTitle),
                  subtitle: Text(l10n.settingsFxRatesSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.goNamed('fx-rates'),
                ),
              ],
            ),
          ),
          // ── Appearance ──
          GlassSectionHeader(title: l10n.settingsAppearanceSection),
          LiquidGlassCard(
            layer: GlassLayer.tertiary,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.s16,
                    vertical: Spacing.s8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.brightness_6_outlined),
                      const SizedBox(width: Spacing.s16),
                      Expanded(
                        child: AppDropdown<ThemeMode>(
                          value: themeMode,
                          label: l10n.settingsThemeModeTitle,
                          items: [
                            for (final m in ThemeMode.values)
                              DropdownMenuItem(
                                value: m,
                                child: Text(_themeModeLabel(l10n, m)),
                              ),
                          ],
                          onChanged: (m) {
                            if (m != null) {
                              Haptics.selection();
                              ref.read(themeModeProvider.notifier).set(m);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.s16,
                    vertical: Spacing.s8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.swap_vert),
                      const SizedBox(width: Spacing.s16),
                      Expanded(
                        child: AppDropdown<MarketColorMode>(
                          value: marketMode,
                          label: l10n.settingsMarketColorTitle,
                          items: [
                            for (final m in MarketColorMode.values)
                              DropdownMenuItem(
                                value: m,
                                child: Text(_marketModeLabel(l10n, m)),
                              ),
                          ],
                          onChanged: (m) {
                            if (m != null) {
                              ref
                                  .read(marketColorModeProvider.notifier)
                                  .set(m);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _MarketColorPreview(),
                ),
              ],
            ),
          ),
          // ── Risk ──
          GlassSectionHeader(title: l10n.settingsRiskSection),
          const LiquidGlassCard(
            layer: GlassLayer.tertiary,
            padding: EdgeInsets.zero,
            child: _RiskThresholdSettings(),
          ),
          // ── Data ──
          GlassSectionHeader(title: l10n.settingsDataSection),
          LiquidGlassCard(
            layer: GlassLayer.tertiary,
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: Text(l10n.settingsDataTitle),
              subtitle: Text(l10n.settingsDataSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.goNamed('backup'),
            ),
          ),
          // ── About ──
          const SizedBox(height: Spacing.s12),
          const LiquidGlassCard(
            layer: GlassLayer.tertiary,
            padding: EdgeInsets.zero,
            child: _AboutTile(),
          ),
        ],
      ),
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

/// "About NaviWealth" tile — version + build + commit SHA, sourced from
/// `package_info_plus` so the binary's actual identity is shown rather
/// than a hard-coded string.
class _AboutTile extends ConsumerWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final versionAsync = ref.watch(appVersionProvider);
    final subtitle = versionAsync.when(
      loading: () => l10n.settingsAboutSubtitle('…'),
      error: (_, _) => l10n.settingsAboutSubtitle('?'),
      data: (info) {
        final base = l10n.settingsAboutSubtitle('${info.version}+${info.buildNumber}');
        // Hide the SHA in dev builds so the line stays compact when the
        // define isn't passed (local `flutter run`).
        if (info.commitSha == 'dev' || info.commitSha.isEmpty) return base;
        final shortSha = info.commitSha.length >= 7
            ? info.commitSha.substring(0, 7)
            : info.commitSha;
        return '$base · $shortSha';
      },
    );
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(l10n.settingsAboutTitle),
      subtitle: Text(subtitle),
    );
  }
}

class _MarketColorPreview extends StatelessWidget {
  const _MarketColorPreview();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: Spacing.s8,
      runSpacing: Spacing.s8,
      children: [
        DeltaChip(value: 1.23, format: DeltaFormat.percent),
        DeltaChip(value: -0.42, format: DeltaFormat.percent),
        DeltaChip(value: 0, format: DeltaFormat.percent),
      ],
    );
  }
}

/// Concentration-risk threshold sliders under Settings → Risk Preferences.
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
          subtitle: l10n.settingsRiskAssetSubtitle,
          value: thresholds.assetWarning,
          onChanged: (v) =>
              ref.read(concentrationThresholdsProvider.notifier).updateAsset(v),
        ),
        _ThresholdSlider(
          icon: Icons.category_outlined,
          label: l10n.settingsRiskSectorLabel,
          subtitle: l10n.settingsRiskSectorSubtitle,
          value: thresholds.sectorWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateSector(v),
        ),
        _ThresholdSlider(
          icon: Icons.public,
          label: l10n.settingsRiskRegionLabel,
          subtitle: l10n.settingsRiskRegionSubtitle,
          value: thresholds.regionWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateRegion(v),
        ),
        _ThresholdSlider(
          icon: Icons.currency_exchange,
          label: l10n.settingsRiskCurrencyLabel,
          subtitle: l10n.settingsRiskCurrencySubtitle,
          value: thresholds.currencyWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateCurrency(v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.tertiary(
              label: l10n.settingsRiskResetDefaults,
              onPressed: () => ref
                  .read(concentrationThresholdsProvider.notifier)
                  .resetToDefaults(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value,
                  min: 0.05,
                  max: 0.95,
                  divisions: 18,
                  label: '${(value * 100).round()}%',
                  onChanged: onChanged,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(value * 100).round()}%',
                  style: theme.textTheme.titleSmall,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
