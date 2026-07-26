import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/income_strategy/application/wheel_strategy_view.dart';
import 'package:naviwealth/features/finance/income_strategy/data/providers.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../domain/leaps_call_position.dart';
import '../domain/trade_journal_entry.dart';
import '../domain/wheel_lifecycle.dart';
import 'income_planner_labels.dart';
import 'leaps_call_position_sheet.dart';
import 'trade_journal_sheet.dart';

/// `/plan/wheel` — per-underlying Wheel cycle review
/// (`docs/domains/options-income.md` §12 P4).
///
/// Reads the generic FinanceOS income strategy composition and projects its
/// Wheel/LEAPS sleeves into a dedicated lifecycle drill-down.
/// Each underlying renders as one tile showing the current stage,
/// cumulative income, and whether a position is open.
class WheelLifecyclePage extends ConsumerWidget {
  const WheelLifecyclePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final overlaysAsync = ref.watch(wheelStrategyViewsProvider);

    return AppPageScaffold(
      title: l10n.planWheelTitle,
      childPad: false,
      child: overlaysAsync.whenOrLoading(
        context: context,
        error: (_, _) => Center(
          child: AppEmptyState(
            icon: FLucideIcons.refreshCw,
            title: l10n.planWheelEmptyTitle,
          ),
        ),
        data: (overlays) {
          if (overlays.isEmpty) {
            return Center(
              child: AppEmptyState(
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
    final stageLabel = _stageLabel(l10n, cycle.stage);
    return SoftCard.raised(
      onPress: onPress,
      child: FTile(
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: AppOpacity.whisper),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          alignment: Alignment.center,
          child: Icon(
            _stageIcon(cycle.stage),
            size: AppIconSizes.h18,
            color: colors.mutedForeground,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(cycle.symbol)),
            AppBadge(
              label: stageLabel,
              tone: cycle.hasOpenPosition
                  ? AppBadgeTone.accent
                  : AppBadgeTone.neutral,
            ),
          ],
        ),
        subtitle: Text(
          '${_nextActionLabel(l10n, cycle.nextAction)} · '
          '${l10n.incomePlannerWheelOpenCount(cycle.openPositions.length)} · '
          '${l10n.leapsOverlayOpenCount(overlay.openPositions.length)}',
          maxLines: 2,
        ),
        suffix: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              l10n.leapsOverlayCombinedRealized,
              style: context.captionStyle,
            ),
            MoneyText(
              amount: overlay.underlyingRealizedResult.toDouble(),
              currencyCode: cycle.currency,
              showSign: true,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showWheelCycleSheet(
  BuildContext pageContext,
  WheelStrategyView overlay,
) {
  return showAppFormSheet<void>(
    context: pageContext,
    builder: (sheetContext) => _WheelCycleSheet(
      pageContext: pageContext,
      sheetContext: sheetContext,
      overlay: overlay,
    ),
  );
}

class _WheelCycleSheet extends StatelessWidget {
  const _WheelCycleSheet({
    required this.pageContext,
    required this.sheetContext,
    required this.overlay,
  });

  final BuildContext pageContext;
  final BuildContext sheetContext;
  final WheelStrategyView overlay;

  WheelLifecycle get cycle => overlay.wheel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: cycle.symbol,
      subtitle: _stageLabel(l10n, cycle.stage),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoftCard.flat(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.incomePlannerWheelNextActionTitle,
                  style: context.captionLabelStyle,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  _nextActionLabel(l10n, cycle.nextAction),
                  style: context.bodyCaptionStyle,
                ),
              ],
            ),
          ),
          if (cycle.openPositions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.incomePlannerWheelOpenPositionsTitle,
              style: context.mutedLabelStyle,
            ),
            const SizedBox(height: AppSpacing.s8),
            for (final entry in cycle.openPositions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                child: _OpenPositionTile(
                  entry: entry,
                  onPress: () => _openJournal(entry.id),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.s16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.leapsOverlayTitle,
                      style: context.mutedLabelStyle,
                    ),
                    Text(
                      l10n.leapsOverlaySubtitle,
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              FButton(
                onPress: _openNewLeaps,
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
          const SizedBox(height: AppSpacing.s8),
          _OverlayMetrics(overlay: overlay),
          if (overlay.positions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            for (final position in overlay.positions.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                child: _LeapsPositionTile(
                  position: position,
                  onPress: () => _openLeaps(position.id),
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              child: Text(l10n.leapsOverlayEmpty, style: context.captionStyle),
            ),
          if (overlay.risks.isNotEmpty || overlay.openPositions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            _OverlayWarnings(risks: overlay.risks),
          ],
          const SizedBox(height: AppSpacing.s16),
          Text(l10n.planWheelHistoryTitle, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s8),
          for (final entry in cycle.entries.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: _WheelHistoryTile(
                entry: entry,
                onPress: () => _openJournal(entry.id),
              ),
            ),
          const SizedBox(height: AppSpacing.s8),
          FButton(
            onPress: () => _openJournal(null),
            child: Text(l10n.incomePlannerJournalAddCta),
          ),
        ],
      ),
    );
  }

  void _openJournal(String? existingId) {
    Navigator.of(sheetContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!pageContext.mounted) return;
      showTradeJournalSheet(pageContext, existingId: existingId);
    });
  }

  void _openNewLeaps() => _openLeaps(null);

  void _openLeaps(String? existingId) {
    Navigator.of(sheetContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!pageContext.mounted) return;
      showLeapsCallPositionSheet(
        pageContext,
        existingId: existingId,
        symbol: cycle.symbol,
      );
    });
  }
}

class _OverlayMetrics extends StatelessWidget {
  const _OverlayMetrics({required this.overlay});

  final WheelStrategyView overlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final coverage = overlay.wheelIncomeCoverageRatio;
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Wrap(
        spacing: AppSpacing.s16,
        runSpacing: AppSpacing.s12,
        children: [
          _Metric(
            label: l10n.leapsOverlayCost,
            value: '${overlay.wheel.currency} ${overlay.openLeapsCost}',
          ),
          _Metric(
            label: l10n.leapsOverlayCoverage,
            value: coverage == null
                ? l10n.leapsOverlayUnknown
                : l10n.leapsOverlayCoverageValue(
                    (coverage.toDouble() * 100).toStringAsFixed(0),
                  ),
          ),
          _Metric(
            label: l10n.leapsOverlayDeltaShares,
            value:
                overlay.deltaEquivalentShares?.toString() ??
                l10n.leapsOverlayUnknown,
          ),
          _Metric(
            label: l10n.leapsOverlayCombinedRealized,
            value:
                '${overlay.wheel.currency} ${overlay.underlyingRealizedResult}',
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 128),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s2),
        Text(value, style: context.labelStyle),
      ],
    ),
  );
}

class _LeapsPositionTile extends StatelessWidget {
  const _LeapsPositionTile({required this.position, required this.onPress});

  final LeapsCallPosition position;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final days = position.expirationAt
        .toUtc()
        .difference(DateTime.now().toUtc())
        .inDays;
    return SoftCard.flat(
      onPress: onPress,
      padding: const EdgeInsets.all(AppSpacing.s12),
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
                      ? l10n.incomePlannerWheelDueSummary(
                          MaterialLocalizations.of(
                            context,
                          ).formatShortDate(position.expirationAt.toLocal()),
                          days,
                        )
                      : '${l10n.leapsOverlayExpiration}: '
                            '${MaterialLocalizations.of(context).formatShortDate(position.expirationAt.toLocal())}',
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          AppBadge(
            label: _leapsStatusLabel(l10n, position.status),
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

String _leapsStatusLabel(AppLocalizations l10n, LeapsCallStatus status) =>
    switch (status) {
      LeapsCallStatus.open => l10n.leapsOverlayStatusOpen,
      LeapsCallStatus.closed => l10n.leapsOverlayStatusClosed,
      LeapsCallStatus.exercised => l10n.leapsOverlayStatusExercised,
      LeapsCallStatus.expired => l10n.leapsOverlayStatusExpired,
    };

class _OverlayWarnings extends StatelessWidget {
  const _OverlayWarnings({required this.risks});

  final List<IncomeStrategyRisk> risks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final risk in risks)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(FLucideIcons.triangleAlert, size: AppIconSizes.sm),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      _warningLabel(l10n, risk.code),
                      style: context.bodyCaptionStyle,
                    ),
                  ),
                ],
              ),
            ),
          Text(l10n.leapsOverlayRiskDividend, style: context.bodyCaptionStyle),
        ],
      ),
    );
  }
}

String _warningLabel(AppLocalizations l10n, IncomeStrategyRiskCode warning) =>
    switch (warning) {
      IncomeStrategyRiskCode.stackedDownside => l10n.leapsOverlayRiskStacked,
      IncomeStrategyRiskCode.leapsCostNotCovered => l10n.leapsOverlayRiskCost,
      IncomeStrategyRiskCode.missingDelta => l10n.leapsOverlayRiskDelta,
      IncomeStrategyRiskCode.missingMarketValue => l10n.leapsOverlayRiskMark,
      IncomeStrategyRiskCode.expirationNear => l10n.leapsOverlayRiskExpiry,
      IncomeStrategyRiskCode.unplannedSleeve =>
        l10n.incomeStrategyRiskUnplanned,
      IncomeStrategyRiskCode.capitalBudgetExceeded =>
        l10n.incomeStrategyRiskCapitalBudget,
      IncomeStrategyRiskCode.assignmentBudgetExceeded =>
        l10n.incomeStrategyRiskAssignment,
      IncomeStrategyRiskCode.concentrationExceeded =>
        l10n.incomeStrategyRiskConcentration,
      IncomeStrategyRiskCode.dividendInterruption =>
        l10n.incomeStrategyRiskDividend,
      IncomeStrategyRiskCode.leapsBudgetExceeded =>
        l10n.incomeStrategyRiskLeapsBudget,
    };

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
        : l10n.incomePlannerWheelDueSummary(
            MaterialLocalizations.of(
              context,
            ).formatShortDate(expiration.toLocal()),
            expiration.toUtc().difference(DateTime.now().toUtc()).inDays,
          );
    return SoftCard.flat(
      onPress: onPress,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(entry.optionSymbol, style: context.labelStyle),
              ),
              AppBadge(
                label: optionsStrategyKindShortLabel(l10n, entry.strategy),
                tone: AppBadgeTone.accent,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(due, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.incomePlannerJournalQuantitySummary(
              entry.contractQuantity,
              entry.effectiveContractSize,
            ),
            style: context.captionStyle,
          ),
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
      onPress: onPress,
      padding: const EdgeInsets.all(AppSpacing.s12),
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

IconData _stageIcon(WheelStage stage) => switch (stage) {
  WheelStage.between => FLucideIcons.circle,
  WheelStage.cashWaiting => FLucideIcons.wallet,
  WheelStage.shortPut => FLucideIcons.arrowDownLeft,
  WheelStage.putExpired => FLucideIcons.circleCheck,
  WheelStage.putAssigned => FLucideIcons.logIn,
  WheelStage.sharesHeld => FLucideIcons.package,
  WheelStage.shortCall => FLucideIcons.arrowUpRight,
  WheelStage.mixedOpen => FLucideIcons.layers3,
  WheelStage.callExpired => FLucideIcons.circleCheck,
  WheelStage.callCalled => FLucideIcons.logOut,
};

/// Labels are pinned in code (not l10n) because the Wheel stages are a
/// canonical strategy taxonomy — translating "short put" into a free
/// rendering for each locale would lose the strategy semantics.
String _stageLabel(AppLocalizations l10n, WheelStage stage) => switch (stage) {
  WheelStage.between => l10n.planWheelStageBetween,
  WheelStage.cashWaiting => l10n.planWheelStageCashWaiting,
  WheelStage.shortPut => l10n.planWheelStageShortPut,
  WheelStage.putExpired => l10n.planWheelStagePutExpired,
  WheelStage.putAssigned => l10n.planWheelStagePutAssigned,
  WheelStage.sharesHeld => l10n.planWheelStageSharesHeld,
  WheelStage.shortCall => l10n.planWheelStageShortCall,
  WheelStage.mixedOpen => l10n.planWheelStageMixedOpen,
  WheelStage.callExpired => l10n.planWheelStageCallExpired,
  WheelStage.callCalled => l10n.planWheelStageCallCalled,
};

String _nextActionLabel(
  AppLocalizations l10n,
  WheelNextAction action,
) => switch (action) {
  WheelNextAction.reviewOpenPositions => l10n.incomePlannerWheelNextReviewOpen,
  WheelNextAction.waitForPut => l10n.incomePlannerWheelNextWaitPut,
  WheelNextAction.recordPutOutcome => l10n.incomePlannerWheelNextRecordPut,
  WheelNextAction.scanCoveredCall => l10n.incomePlannerWheelNextScanCall,
  WheelNextAction.waitForCall => l10n.incomePlannerWheelNextWaitCall,
  WheelNextAction.recordCallOutcome => l10n.incomePlannerWheelNextRecordCall,
  WheelNextAction.startNewPut => l10n.incomePlannerWheelNextStartPut,
};
