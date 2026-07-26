import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/income_strategy/application/wheel_strategy_view.dart';
import 'package:naviwealth/features/finance/income_strategy/composition/income_strategy_presentation.dart';
import 'package:naviwealth/features/finance/income_strategy/data/providers.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../domain/leaps_call_position.dart';
import '../domain/trade_journal_entry.dart';
import 'income_planner_labels.dart';
import 'leaps_call_position_sheet.dart';
import 'trade_journal_sheet.dart';

/// `/plan/income/wheel` — the single Wheel lifecycle surface
/// (`docs/domains/options-income.md` §12 P4).
///
/// Reads the generic FinanceOS income strategy composition and projects its
/// Wheel/LEAPS sleeves into a per-underlying drill-down. Each underlying
/// renders as one tile showing the current stage, cumulative income, and
/// whether a position is open.
class WheelLifecyclePage extends ConsumerWidget {
  const WheelLifecyclePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (kIsWeb) {
      return AppPageScaffold(
        title: l10n.planWheelTitle,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Text(l10n.incomePlannerUnsupportedOnWeb),
        ),
      );
    }
    final overlaysAsync = ref.watch(wheelStrategyViewsProvider);

    return AppPageScaffold(
      title: l10n.planWheelTitle,
      childPad: false,
      child: overlaysAsync.whenOrLoading(
        context: context,
        error: (error, _) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, error),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(wheelStrategyViewsProvider),
        ),
        data: (overlays) {
          if (overlays.isEmpty) {
            return AppEmptyState(
              icon: FLucideIcons.refreshCw,
              title: l10n.planWheelEmptyTitle,
              message: l10n.planWheelEmptyBody,
              action: Column(
                children: [
                  FButton(
                    onPress: () => showTradeJournalSheet(context),
                    child: Text(l10n.incomePlannerJournalAddCta),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  FButton(
                    variant: FButtonVariant.outline,
                    onPress: () => showLeapsCallPositionSheet(context),
                    child: Text(l10n.leapsOverlayAdd),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s12,
              AppSpacing.s16,
              AppSpacing.s24,
            ),
            itemCount: overlays.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
            itemBuilder: (context, i) => _WheelTile(
              overlay: overlays[i],
              onPress: () => _showWheelCycleSheet(context, overlays[i]),
            ),
          );
        },
      ),
    );
  }
}

class _WheelTile extends StatelessWidget {
  const _WheelTile({required this.overlay, required this.onPress});

  final WheelStrategyView overlay;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final cycle = overlay.wheel;
    return SoftCard.raised(
      onPress: onPress,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: wheelStageIcon(cycle.stage),
            color: cycle.hasOpenPosition
                ? colors.primary
                : colors.mutedForeground,
            size: 36,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(cycle.symbol, style: context.rowTitleStyle),
                    ),
                    AppBadge(
                      label: wheelStageLabel(l10n, cycle.stage),
                      tone: cycle.hasOpenPosition
                          ? AppBadgeTone.accent
                          : AppBadgeTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  '${wheelNextActionLabel(l10n, cycle.nextAction)} · '
                  '${l10n.incomePlannerWheelOpenCount(cycle.openPositions.length)} · '
                  '${l10n.leapsOverlayOpenCount(overlay.openPositions.length)}',
                  style: context.captionStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.leapsOverlayCombinedRealized,
                        style: context.captionStyle,
                      ),
                    ),
                    MoneyText(
                      amount: overlay.underlyingRealizedResult.toDouble(),
                      currencyCode: cycle.currency,
                      showSign: true,
                      style: context.labelStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showWheelCycleSheet(
  BuildContext pageContext,
  WheelStrategyView overlay,
) {
  final l10n = AppLocalizations.of(pageContext);
  return showAppSheet<void>(
    context: pageContext,
    title: overlay.wheel.symbol,
    subtitle: wheelStageLabel(l10n, overlay.wheel.stage),
    builder: (_) =>
        _WheelCycleSheet(pageContext: pageContext, overlay: overlay),
  );
}

class _WheelCycleSheet extends ConsumerWidget {
  const _WheelCycleSheet({required this.pageContext, required this.overlay});

  final BuildContext pageContext;
  final WheelStrategyView overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cycle = overlay.wheel;
    final formatters = context.formatters(ref);
    final presentations = [
      for (final module in ref.watch(incomeStrategyModulesProvider))
        module.presentation,
    ];
    final coverage = overlay.wheelIncomeCoverageRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                wheelNextActionLabel(l10n, cycle.nextAction),
                style: context.bodyCaptionStyle,
              ),
            ),
          ],
        ),
        if (cycle.openPositions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          AppSheetSectionLabel(l10n.incomePlannerWheelOpenPositionsTitle),
          for (final entry in cycle.openPositions)
            _OpenPositionTile(
              entry: entry,
              onPress: () => _openJournal(context, entry.id),
            ),
        ],
        const SizedBox(height: AppSpacing.s16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.leapsOverlayTitle, style: context.mutedLabelStyle),
                  Text(l10n.leapsOverlaySubtitle, style: context.captionStyle),
                ],
              ),
            ),
            FButton(
              onPress: () => _openLeaps(context, null),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
                  const SizedBox(width: AppSpacing.s4),
                  Text(l10n.leapsOverlayAdd),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        AppMetricCluster(
          dense: true,
          items: [
            AppMetricItem(
              label: l10n.leapsOverlayCost,
              value: formatters.currency(
                overlay.openLeapsCost,
                code: cycle.currency,
              ),
            ),
            AppMetricItem(
              label: l10n.leapsOverlayCoverage,
              value: coverage == null
                  ? l10n.leapsOverlayUnknown
                  : formatters.percent(coverage.toDouble(), decimalDigits: 0),
            ),
            AppMetricItem(
              label: l10n.leapsOverlayDeltaShares,
              value:
                  overlay.deltaEquivalentShares?.toString() ??
                  l10n.leapsOverlayUnknown,
            ),
          ],
        ),
        if (overlay.positions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          for (final position in overlay.positions.reversed)
            _LeapsPositionTile(
              position: position,
              onPress: () => _openLeaps(context, position.id),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
            child: Text(l10n.leapsOverlayEmpty, style: context.captionStyle),
          ),
        if (overlay.risks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          AppSheetSectionLabel(l10n.incomeStrategyRisksTitle),
          for (final risk in overlay.risks)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: _RiskRow(
                label: incomeStrategyRiskLabel(l10n, presentations, risk.code),
                severity: risk.severity,
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.s16),
        AppSheetSectionLabel(l10n.planWheelHistoryTitle),
        for (final entry in cycle.entries.reversed)
          _WheelHistoryTile(
            entry: entry,
            onPress: () => _openJournal(context, entry.id),
          ),
        const SizedBox(height: AppSpacing.s8),
        FButton(
          onPress: () => _openJournal(context, null),
          child: Text(l10n.incomePlannerJournalAddCta),
        ),
      ],
    );
  }

  void _openJournal(BuildContext sheetContext, String? existingId) {
    closeSheetThen(sheetContext, () {
      if (!pageContext.mounted) return;
      showTradeJournalSheet(pageContext, existingId: existingId);
    });
  }

  void _openLeaps(BuildContext sheetContext, String? existingId) {
    closeSheetThen(sheetContext, () {
      if (!pageContext.mounted) return;
      showLeapsCallPositionSheet(
        pageContext,
        existingId: existingId,
        symbol: overlay.wheel.symbol,
      );
    });
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.label, required this.severity});

  final String label;
  final IncomeStrategyRiskSeverity severity;

  @override
  Widget build(BuildContext context) {
    final semantic = SemanticColors.of(context);
    final color = switch (severity) {
      IncomeStrategyRiskSeverity.info => context.theme.colors.mutedForeground,
      IncomeStrategyRiskSeverity.warning => semantic.warning,
      IncomeStrategyRiskSeverity.critical => semantic.danger,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(FLucideIcons.triangleAlert, size: AppIconSizes.sm, color: color),
        const SizedBox(width: AppSpacing.s8),
        Expanded(child: Text(label, style: context.bodyCaptionStyle)),
      ],
    );
  }
}

class _LeapsPositionTile extends StatelessWidget {
  const _LeapsPositionTile({required this.position, required this.onPress});

  final LeapsCallPosition position;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expiration = MaterialLocalizations.of(
      context,
    ).formatShortDate(position.expirationAt.toLocal());
    return SoftCard.flat(
      borderless: true,
      tinted: false,
      onPress: onPress,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(position.optionSymbol, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  position.isOpen
                      ? _dueOrExpired(l10n, expiration, position.expirationAt)
                      : '${l10n.leapsOverlayExpiration}: $expiration',
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          AppBadge(
            label: leapsCallStatusLabel(l10n, position.status),
            tone: position.isOpen ? AppBadgeTone.accent : AppBadgeTone.neutral,
          ),
          const SizedBox(width: AppSpacing.s8),
          MoneyText(
            amount: position.grossEntryCost.toDouble(),
            currencyCode: position.currency,
          ),
          const SizedBox(width: AppSpacing.s8),
          const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
        ],
      ),
    );
  }
}

class _OpenPositionTile extends StatelessWidget {
  const _OpenPositionTile({required this.entry, required this.onPress});

  final TradeJournalEntry entry;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expiration = entry.expirationAt;
    final due = expiration == null
        ? l10n.incomePlannerWheelExpirationMissing
        : _dueOrExpired(
            l10n,
            MaterialLocalizations.of(
              context,
            ).formatShortDate(expiration.toLocal()),
            expiration,
          );
    return SoftCard.flat(
      borderless: true,
      tinted: false,
      onPress: onPress,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.optionSymbol, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(due, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.incomePlannerJournalQuantitySummary(
                    entry.contractQuantity,
                    entry.effectiveContractSize,
                  ),
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          AppBadge(
            label: optionsStrategyKindShortLabel(l10n, entry.strategy),
            tone: AppBadgeTone.accent,
          ),
          const SizedBox(width: AppSpacing.s8),
          const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
        ],
      ),
    );
  }
}

class _WheelHistoryTile extends StatelessWidget {
  const _WheelHistoryTile({required this.entry, required this.onPress});

  final TradeJournalEntry entry;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      borderless: true,
      tinted: false,
      onPress: onPress,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.optionSymbol, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  tradeJournalStatusLabel(l10n, entry.status),
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
        ],
      ),
    );
  }
}

String _dueOrExpired(
  AppLocalizations l10n,
  String position,
  DateTime expiration,
) {
  final days = expiration.toUtc().difference(DateTime.now().toUtc()).inDays;
  return days < 0
      ? l10n.incomePlannerWheelExpiredSummary(position, -days)
      : l10n.incomePlannerWheelDueSummary(position, days);
}
