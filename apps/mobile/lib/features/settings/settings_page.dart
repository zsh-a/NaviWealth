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
      appBar: AppBar(title: Text(l10n.settingsAppBarTitle)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(l10n.settingsAccountTitle),
            subtitle: Text(l10n.settingsAccountSubtitle),
          ),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: Text(l10n.settingsDevicesTitle),
            subtitle: Text(l10n.settingsDevicesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('devices'),
          ),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: Text(l10n.settingsBaseCurrencyTitle),
            subtitle: Text(l10n.settingsBaseCurrencyHint),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  baseCurrency,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: Spacing.s4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _pickBaseCurrency(context, ref, baseCurrency),
          ),
          ListTile(
            leading: const Icon(Icons.published_with_changes_outlined),
            title: Text(l10n.settingsFxRatesTitle),
            subtitle: Text(l10n.settingsFxRatesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('fx-rates'),
          ),
          const Divider(),
          _SectionHeader(label: l10n.settingsAppearanceSection),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(l10n.settingsThemeModeTitle),
            subtitle: Text(_themeModeLabel(l10n, themeMode)),
            trailing: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto),
                  tooltip: l10n.themeModeSystem,
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_outlined),
                  tooltip: l10n.themeModeLight,
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_outlined),
                  tooltip: l10n.themeModeDark,
                ),
              ],
              selected: {themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                Haptics.selection();
                ref.read(themeModeProvider.notifier).set(s.first);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: Text(l10n.settingsMarketColorTitle),
            subtitle: Text(_marketModeLabel(l10n, marketMode)),
            trailing: PopupMenuButton<MarketColorMode>(
              icon: const Icon(Icons.tune),
              onSelected: (m) =>
                  ref.read(marketColorModeProvider.notifier).set(m),
              itemBuilder: (context) => [
                for (final m in MarketColorMode.values)
                  PopupMenuItem(
                    value: m,
                    child: Row(
                      children: [
                        if (m == marketMode)
                          const Icon(Icons.check, size: 18)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Text(_marketModeLabel(l10n, m)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _MarketColorPreview(),
          ),
          const Divider(),
          _SectionHeader(label: l10n.settingsRiskSection),
          const _RiskThresholdSettings(),
          const Divider(),
          const _AboutTile(),
        ],
      ),
    );
  }

  Future<void> _pickBaseCurrency(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.s16,
                  vertical: Spacing.s8,
                ),
                child: Text(
                  l10n.settingsBaseCurrencySheetTitle,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final option in kCommonCurrencies)
                      ListTile(
                        title: Text(option.label),
                        trailing: option.code == current
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.of(ctx).pop(option.code),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != current) {
      await ref.read(baseCurrencyProvider.notifier).set(picked);
    }
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
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
            child: TextButton(
              onPressed: () => ref
                  .read(concentrationThresholdsProvider.notifier)
                  .resetToDefaults(),
              child: Text(l10n.settingsRiskResetDefaults),
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
