import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/trade_journal_entry.dart';
import '../domain/wheel_lifecycle.dart';
import 'income_planner_labels.dart';
import 'trade_journal_sheet.dart';

/// `/plan/wheel` — per-underlying Wheel cycle review
/// (`docs/domains/options-income.md` §12 P4).
///
/// Reads [wheelLifecyclesProvider] which derives cycles from the
/// existing trade journal stream — no new sync table, no extra IO.
/// Each underlying renders as one tile showing the current stage,
/// cumulative income, and whether a position is open.
class WheelLifecyclePage extends ConsumerWidget {
  const WheelLifecyclePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final cyclesAsync = ref.watch(wheelLifecyclesProvider);

    return AppPageScaffold(
      title: l10n.planWheelTitle,
      childPad: false,
      child: cyclesAsync.whenOrLoading(
        context: context,
        error: (_, _) => Center(
          child: AppEmptyState(
            icon: FLucideIcons.refreshCw,
            title: l10n.planWheelEmptyTitle,
          ),
        ),
        data: (cycles) {
          if (cycles.isEmpty) {
            return Center(
              child: AppEmptyState(
                icon: FLucideIcons.refreshCw,
                title: l10n.planWheelEmptyTitle,
                message: l10n.planWheelEmptyBody,
                action: FButton(
                  onPress: () => showTradeJournalSheet(context),
                  child: Text(l10n.incomePlannerJournalAddCta),
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
            itemCount: cycles.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
            itemBuilder: (context, i) => _WheelTile(
              cycle: cycles[i],
              onPress: () => _showWheelCycleSheet(context, cycles[i]),
            ),
          );
        },
      ),
    );
  }
}

class _WheelTile extends StatelessWidget {
  const _WheelTile({required this.cycle, required this.onPress});

  final WheelLifecycle cycle;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
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
          '${l10n.incomePlannerWheelOpenCount(cycle.openPositions.length)}',
          maxLines: 2,
        ),
        suffix: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              l10n.incomePlannerWheelRealizedIncome,
              style: context.captionStyle,
            ),
            MoneyText(
              amount: cycle.cumulativeIncome.toDouble(),
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
  WheelLifecycle cycle,
) {
  return showAppFormSheet<void>(
    context: pageContext,
    builder: (sheetContext) => _WheelCycleSheet(
      pageContext: pageContext,
      sheetContext: sheetContext,
      cycle: cycle,
    ),
  );
}

class _WheelCycleSheet extends StatelessWidget {
  const _WheelCycleSheet({
    required this.pageContext,
    required this.sheetContext,
    required this.cycle,
  });

  final BuildContext pageContext;
  final BuildContext sheetContext;
  final WheelLifecycle cycle;

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
