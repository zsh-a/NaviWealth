import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../analytics/data/risk_threshold_preferences.dart';
import '../../expense/data/expense_report_providers.dart';
import '../../fire/data/fire_plan_preferences.dart';
import '../../fire/domain/fire_plan.dart';
import '../../rebalance/data/rebalance_providers.dart';
import '../../rebalance/domain/allocation_schemes.dart';
import '../../rebalance/ui/target_allocation_editor_sheet.dart';
import '../../shared/forms/currency_picker.dart';
import '../data/base_currency_preference.dart';
import '../data/risk_appetite_preferences.dart';
import 'inline_setting_row.dart';

/// FinanceOS-specific settings shown inside LifeOS domain management.
///
/// These rows are intentionally not on the Settings overview: most of
/// them alter Plan/FIRE/rebalance behavior, so they need the extra
/// context of the always-on FinanceOS domain.
class FinanceDomainSettingsSection extends ConsumerWidget {
  const FinanceDomainSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        children: [
          const _FinanceHeaderRow(),
          const AppDivider(),
          const _NumbersAndMoneyRows(),
          const AppDivider(),
          const _RiskAppetiteRow(),
          const AppDivider(),
          _TargetAllocationLink(
            onTap: () => showTargetAllocationEditorSheet(context: context),
          ),
          const AppDivider(),
          _MonthlyExpenseLink(
            onTap: () => context.goNamed(AppRouteNames.monthlyExpense),
          ),
          const AppDivider(),
          _RiskThresholdsLink(
            onTap: () => context.goNamed(AppRouteNames.riskThresholds),
          ),
          const AppDivider(),
          _StressTestLink(
            onTap: () => context.goNamed(AppRouteNames.stressTest),
          ),
        ],
      ),
    );
  }
}

class _FinanceHeaderRow extends StatelessWidget {
  const _FinanceHeaderRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s10,
      ),
      child: Row(
        children: [
          Container(
            width: AppSpacing.s32,
            height: AppSpacing.s32,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              FLucideIcons.walletCards,
              size: AppIconSizes.sm,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('FinanceOS', style: context.theme.typography.sm),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.settingsDomainsFinanceSubtitle,
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          AppBadge(
            label: l10n.settingsDomainsFinanceAlwaysOnBadge.toUpperCase(),
            size: AppBadgeSize.compact,
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
          options: {
            for (final code in kCommonCurrencies)
              currencyDisplayLabel(l10n, code): code,
          },
          onChanged: (picked) =>
              ref.read(baseCurrencyProvider.notifier).set(picked),
        ),
        const AppDivider(),
        InlineLinkRow(
          icon: FLucideIcons.refreshCw,
          label: l10n.settingsFxRatesTitle,
          subtitle: l10n.settingsFxRatesSubtitle,
          onTap: () => context.goNamed(AppRouteNames.fxRates),
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
    final colors = context.theme.colors;
    final appetite = ref.watch(riskAppetiteProvider);
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
              Icon(
                FLucideIcons.slidersHorizontal,
                size: AppIconSizes.h18,
                color: colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s12),
              Text(
                l10n.settingsRiskAppetiteLabel,
                style: context.theme.typography.sm,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s6,
            runSpacing: AppSpacing.s6,
            children: [
              for (final option in _appetiteOptionsForChips(l10n))
                _SettingsChoicePill(
                  label: option.label,
                  selected: appetite == option.value,
                  onTap: () => _onPick(context, ref, option.value),
                ),
            ],
          ),
        ],
      ),
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
    if (next != RiskAppetite.custom) {
      await ref
          .read(targetAllocationProvider.notifier)
          .update(allocationScheme(schemePresetFor(next)));
    }
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

class _SettingsChoicePill extends StatelessWidget {
  const _SettingsChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onTap,
      child: AnimatedContainer(
        duration: Motion.medium,
        curve: Motion.standardDecelerate,
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s6,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: AppOpacity.subtle)
              : colors.muted.withValues(alpha: AppOpacity.faint),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.prominent)
                : colors.border.withValues(alpha: AppOpacity.muted),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: AppOpacity.faint),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: selected
              ? context.captionLabelStyle.copyWith(color: colors.primary)
              : context.theme.typography.xs.copyWith(
                  color: colors.foreground,
                  fontWeight: FontWeight.w500,
                ),
        ),
      ),
    );
  }
}

class _AppetiteOption {
  const _AppetiteOption(this.value, this.label);
  final RiskAppetite value;
  final String label;
}

List<_AppetiteOption> _appetiteOptionsForChips(AppLocalizations l10n) {
  return [
    _AppetiteOption(
      RiskAppetite.conservative,
      l10n.settingsRiskAppetiteConservative,
    ),
    _AppetiteOption(RiskAppetite.moderate, l10n.settingsRiskAppetiteModerate),
    _AppetiteOption(
      RiskAppetite.aggressive,
      l10n.settingsRiskAppetiteAggressive,
    ),
    _AppetiteOption(RiskAppetite.custom, l10n.settingsRiskAppetiteCustom),
  ];
}

class _TargetAllocationLink extends ConsumerWidget {
  const _TargetAllocationLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appetite = ref.watch(riskAppetiteProvider);
    final subtitle = switch (appetite) {
      RiskAppetite.conservative => l10n.settingsRiskAppetiteConservative,
      RiskAppetite.moderate => l10n.settingsRiskAppetiteModerate,
      RiskAppetite.aggressive => l10n.settingsRiskAppetiteAggressive,
      RiskAppetite.custom => l10n.settingsRiskAppetiteCustom,
    };
    return InlineLinkRow(
      icon: FLucideIcons.chartPie,
      label: l10n.settingsTargetAllocationLabel,
      subtitle: subtitle,
      trailingBadge: appetite == RiskAppetite.custom
          ? l10n.settingsBadgeCustom
          : l10n.settingsBadgeAuto,
      onTap: onTap,
    );
  }
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
      trailingBadge: isCustom
          ? l10n.settingsBadgeCustom
          : l10n.settingsBadgeAuto,
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
    final risk = ref.watch(firePlanExtrasProvider).riskSettings;
    final isCustom = risk != const FireRiskSettings();
    return InlineLinkRow(
      icon: FLucideIcons.flaskConical,
      label: l10n.settingsStressTestLabel,
      trailingBadge: isCustom
          ? l10n.settingsBadgeCustom
          : l10n.settingsBadgeAuto,
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
      trailingBadge: isOverride
          ? l10n.settingsBadgeCustom
          : l10n.settingsBadgeAuto,
      onTap: onTap,
    );
  }
}
