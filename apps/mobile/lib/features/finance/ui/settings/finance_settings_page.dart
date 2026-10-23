import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/analytics/data/risk_threshold_preferences.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/preferences/risk_appetite_preferences.dart';
import 'package:naviwealth/features/finance/expense/data/expense_report_providers.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';

import '../../../../core/forms/currency_picker.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Domain-owned finance preferences, opened from Settings → Domains.
class FinanceSettingsPage extends StatelessWidget {
  const FinanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.settingsDomainsConfigure('FinanceOS'),
      childPad: false,
      child: SettingsPageFrame(
        children: [
          AppGroupedSurface(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: [
                const _NumbersAndMoneyRows(),
                const AppGroupedDivider(),
                const _RiskAppetiteRow(),
                const AppGroupedDivider(),
                _MonthlyExpenseLink(
                  onTap: () =>
                      context.pushNamed(SettingsRouteNames.monthlyExpense),
                ),
                const AppGroupedDivider(),
                _RiskThresholdsLink(
                  onTap: () =>
                      context.pushNamed(SettingsRouteNames.riskThresholds),
                ),
                const AppGroupedDivider(),
                _StressTestLink(
                  onTap: () => context.pushNamed(SettingsRouteNames.stressTest),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumbersAndMoneyRows extends ConsumerWidget {
  const _NumbersAndMoneyRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);

    return Column(
      children: [
        InlineSettingRow<String>(
          icon: FLucideIcons.arrowLeftRight,
          label: l10n.settingsBaseCurrencyTitle,
          value: baseCurrency,
          stackValue: true,
          options: {
            for (final code in kCommonCurrencies)
              currencyDisplayLabel(l10n, code): code,
          },
          onChanged: (picked) =>
              ref.read(baseCurrencyProvider.notifier).set(picked),
        ),
        const AppGroupedDivider(),
        InlineLinkRow(
          icon: FLucideIcons.refreshCw,
          label: l10n.settingsFxRatesTitle,
          subtitle: l10n.settingsFxRatesSubtitle,
          onTap: () => context.pushNamed(SettingsRouteNames.fxRates),
        ),
      ],
    );
  }
}

class _RiskAppetiteRow extends ConsumerWidget {
  const _RiskAppetiteRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appetite = ref.watch(riskAppetiteProvider);
    return InlineSettingRow<RiskAppetite>(
      icon: FLucideIcons.slidersHorizontal,
      label: l10n.settingsRiskAppetiteLabel,
      value: appetite,
      stackValue: true,
      options: {
        for (final option in RiskAppetite.values)
          _appetiteLabel(l10n, option): option,
      },
      onChanged: (value) => _onPick(context, ref, value),
    );
  }

  Future<void> _onPick(
    BuildContext context,
    WidgetRef ref,
    RiskAppetite next,
  ) async {
    final current = ref.read(riskAppetiteProvider);
    if (current == next) return;
    if (next != RiskAppetite.custom) {
      final l10n = AppLocalizations.of(context);
      final confirmed = await showConfirmDialog(
        context: context,
        title: Text(l10n.settingsRiskAppetiteConfirmTitle),
        body: Text(
          l10n.settingsRiskAppetiteConfirmBody(_appetiteLabel(l10n, next)),
        ),
        cancelLabel: l10n.commonCancel,
        confirmLabel: l10n.settingsRiskAppetiteConfirmAction,
        icon: FLucideIcons.slidersHorizontal,
      );
      if (confirmed != true || !context.mounted) return;
    }
    final priorThresholds = ref.read(concentrationThresholdsProvider);
    await ref.read(riskAppetiteProvider.notifier).set(next);
    if (isAtAnyAppetitePreset(priorThresholds)) {
      await ref
          .read(concentrationThresholdsProvider.notifier)
          .applyAll(concentrationThresholdsForAppetite(next));
    }
  }
}

String _appetiteLabel(AppLocalizations l10n, RiskAppetite appetite) {
  return switch (appetite) {
    RiskAppetite.conservative => l10n.settingsRiskAppetiteConservative,
    RiskAppetite.moderate => l10n.settingsRiskAppetiteModerate,
    RiskAppetite.aggressive => l10n.settingsRiskAppetiteAggressive,
    RiskAppetite.custom => l10n.settingsRiskAppetiteCustom,
  };
}

class _RiskThresholdsLink extends ConsumerWidget {
  const _RiskThresholdsLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final thresholds = ref.watch(concentrationThresholdsProvider);
    final isCustom = !isAtAnyAppetitePreset(thresholds);
    return InlineLinkRow(
      icon: FLucideIcons.bellRing,
      label: l10n.settingsRiskThresholdsLabel,
      trailingBadge: isCustom ? l10n.settingsBadgeCustom : null,
      onTap: onTap,
    );
  }
}

class _StressTestLink extends ConsumerWidget {
  const _StressTestLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final risk = ref.watch(firePlanProvider).riskSettings;
    final isCustom = risk != const FireRiskSettings();
    return InlineLinkRow(
      icon: FLucideIcons.flaskConical,
      label: l10n.settingsStressTestLabel,
      trailingBadge: isCustom ? l10n.settingsBadgeCustom : null,
      onTap: onTap,
    );
  }
}

class _MonthlyExpenseLink extends ConsumerWidget {
  const _MonthlyExpenseLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(monthlyExpensePreferencesProvider);
    final isOverride = prefs.override != null;
    final subtitle = isOverride
        ? l10n.settingsMonthlyExpenseSubtitleOverride
        : l10n.settingsMonthlyExpenseSubtitleAuto(prefs.windowMonths);
    return InlineLinkRow(
      icon: FLucideIcons.calendarDays,
      label: l10n.settingsMonthlyExpenseLabel,
      subtitle: subtitle,
      trailingBadge: isOverride ? l10n.settingsBadgeCustom : null,
      onTap: onTap,
    );
  }
}
