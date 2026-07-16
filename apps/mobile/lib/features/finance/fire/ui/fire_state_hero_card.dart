import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/composition/ask_ai.dart';
import 'package:naviwealth/core/ai/intent/ai_intent_invocation.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/fire_providers.dart';
import '../domain/fire_action.dart';
import '../domain/fire_projection.dart';
import '../domain/fire_state.dart';
import 'fire_status_colors.dart';

/// Single visual anchor for the FIRE page: ETA, progress, and key rates.
class FireStateHeroCard extends ConsumerWidget {
  const FireStateHeroCard({super.key, required this.view});

  final FireDashboardView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stateAsync = ref.watch(fireStateProvider);
    final aiAvailable = ref.watch(deviceLlmAvailableProvider);
    VoidCallback? explain;
    if (aiAvailable) {
      explain = () {
        askAi(
          context,
          ref,
          source: 'fire_os_hero',
          intent: 'explain_fire_state',
          object: const AiObjectRef(type: 'fire_state', id: 'default'),
          attrs: const <String, Object?>{'surface': 'fire_os_hero'},
          objectLabel: l10n.fireOsHeroTitle,
        );
      };
    }
    return stateAsync.when(
      loading: () => const _HeroSkeleton(),
      error: (e, _) => _HeroErrorCard(message: '$e'),
      data: (state) =>
          _HeroBody(l10n: l10n, state: state, view: view, onExplain: explain),
    );
  }
}

class _HeroBody extends ConsumerWidget {
  const _HeroBody({
    required this.l10n,
    required this.state,
    required this.view,
    required this.onExplain,
  });

  final AppLocalizations l10n;
  final FireState state;
  final FireDashboardView view;
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    final accent = fireSafetyColor(
      SemanticColors.of(context),
      state.safetyLevel,
    );
    final safetyLabel = _safetyLabel(l10n, state.safetyLevel);
    final progress = view.progressRatio ?? 0;
    final etaMonths = state.fireEtaMonths ?? view.sensitivity.baselineMonths;
    final etaHeadline = _etaHeadline(l10n, etaMonths);
    final swrMonthly = view.safeMonthlyWithdrawalAmount;

    return SoftCard.hero(
      padding: AppPageRhythm.heroPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.fireOsHeroTitle,
                  style: context.mutedLabelStyle,
                ),
              ),
              AppBadge(
                label: safetyLabel,
                foregroundColor: accent,
                containerColor: accent.withValues(alpha: AppOpacity.light),
                borderColor: accent.withValues(alpha: AppOpacity.disabled),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(etaHeadline, style: TypographyTokens.displaySmall),
          const SizedBox(height: AppSpacing.s8),
          // Slim progress rail — replaces the large gauge card.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: SizedBox(
              height: AppSpacing.s6,
              child: Stack(
                children: [
                  ColoredBox(
                    color: context.theme.colors.muted.withValues(
                      alpha: AppOpacity.muted,
                    ),
                    child: const SizedBox.expand(),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: ColoredBox(color: accent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            l10n.fireHeroProgressLine(
              formatters.percent(
                progress,
                decimalDigits: progress >= 0.1 ? 0 : 1,
              ),
              formatters.currency(
                view.currentNetWorth,
                code: view.baseCurrency,
              ),
              formatters.currency(
                view.goal.targetAmount,
                code: view.baseCurrency,
              ),
            ),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppPageRhythm.module),
          // Flat partitions inside the hero — never nested SoftCards.
          AppMetricCluster(
            items: [
              AppMetricItem(
                label: l10n.fireOsHeroWithdrawalRateLabel,
                value: state.withdrawalRate.isFinite
                    ? l10n.fireOsHeroWithdrawalRateValue(
                        (state.withdrawalRate * 100).toStringAsFixed(2),
                        (state.plan.safeWithdrawalRate * 100).toStringAsFixed(1),
                      )
                    : l10n.fireOsHeroWithdrawalRateInfinite,
              ),
              AppMetricItem(
                label: l10n.fireOsHeroCashBucketLabel,
                value: state.cashBucketMonths.isFinite
                    ? l10n.fireOsHeroCashBucketValue(
                        state.cashBucketMonths.toStringAsFixed(1),
                        state.plan.targetCashBucketMonths,
                      )
                    : l10n.fireOsHeroCashBucketInfinite,
              ),
            ],
          ),
          const SizedBox(height: AppPageRhythm.row),
          const AppDivider(horizontalPadding: 0),
          const SizedBox(height: AppPageRhythm.row),
          AppMetricCluster(
            axis: Axis.vertical,
            items: [
              AppMetricItem(
                label: l10n.fireSafeWithdrawalMonthly,
                value: formatters.currency(
                  DecimalX.fromDouble(swrMonthly),
                  code: view.baseCurrency,
                ),
                maxLines: 1,
              ),
            ],
          ),
          if (state.suggestedActions.isNotEmpty) ...[
            const SizedBox(height: AppPageRhythm.module),
            _NextAction(
              action: state.suggestedActions.first,
              formatters: formatters,
              l10n: l10n,
            ),
          ],
          if (onExplain != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FButton(
                variant: FButtonVariant.ghost,
                onPress: onExplain,
                prefix: const Icon(
                  FLucideIcons.sparkles,
                  size: AppIconSizes.xs,
                ),
                child: Text(l10n.aiIntentExplainFireStateLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _etaHeadline(AppLocalizations l10n, int? months) {
    if (months == null) return l10n.fireOsHeroEtaUnreachable;
    if (months == 0) return l10n.fireOsHeroEtaReached;
    final years = months ~/ 12;
    final m = months % 12;
    if (years == 0) return l10n.fireCountdownMonthsOnly(m);
    if (m == 0) return l10n.fireCountdownYearsOnly(years);
    return l10n.fireCountdownYearsMonths(years, m);
  }
}

class _NextAction extends StatelessWidget {
  const _NextAction({
    required this.action,
    required this.formatters,
    required this.l10n,
  });

  final FireAction action;
  final AppFormatters formatters;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final severityColor = fireActionSeverityColor(
      SemanticColors.of(context),
      action.severity,
    );
    final title = fireActionTitle(l10n, action);
    final detail = fireActionDetail(l10n, action, formatters);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: AppSpacing.s6),
          decoration: BoxDecoration(
            color: severityColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.fireHeroNextStepLabel,
                style: context.microCaptionStyle,
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(title, style: context.theme.typography.body.sm),
              if (detail != null) ...[
                const SizedBox(height: AppSpacing.s2),
                Text(detail, style: context.captionStyle),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SoftCard.hero(
      padding: AppPageRhythm.heroPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 120, height: 14, radius: AppRadius.sm),
          SizedBox(height: AppSpacing.s16),
          SkeletonBox(width: 200, height: 32, radius: AppRadius.sm),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(height: 6, radius: AppRadius.full),
        ],
      ),
    );
  }
}

class _HeroErrorCard extends StatelessWidget {
  const _HeroErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SoftCard.raised(
      padding: AppPageRhythm.cardPadding,
      child: Row(
        children: [
          Icon(
            FLucideIcons.circleAlert,
            color: context.theme.colors.destructive,
            size: AppIconSizes.h18,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              message,
              style: context.captionStyle.copyWith(
                color: context.theme.colors.destructive,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

String fireActionTitle(AppLocalizations l10n, FireAction action) {
  switch (action.kind) {
    case FireActionKind.configurePlan:
      return l10n.fireOsActionConfigurePlanTitle;
    case FireActionKind.holdSteady:
      return l10n.fireOsActionHoldSteadyTitle;
    case FireActionKind.topUpCashBucket:
      return l10n.fireOsActionTopUpCashBucketTitle;
    case FireActionKind.reduceSpending:
      return l10n.fireOsActionReduceSpendingTitle;
    case FireActionKind.delayDiscretionary:
      return l10n.fireOsActionDelayDiscretionaryTitle;
    case FireActionKind.rebalance:
      return l10n.fireOsActionRebalanceTitle;
    case FireActionKind.buildRiskReserve:
      return l10n.fireOsActionBuildRiskReserveTitle;
    case FireActionKind.runReview:
      return l10n.fireOsActionRunReviewTitle;
    case FireActionKind.fixCurrencyGap:
      return l10n.fireOsActionFixCurrencyGapTitle;
  }
}

String? fireActionDetail(
  AppLocalizations l10n,
  FireAction action,
  AppFormatters formatters,
) {
  switch (action.kind) {
    case FireActionKind.configurePlan:
      return l10n.fireOsActionConfigurePlanDetail;
    case FireActionKind.holdSteady:
      return l10n.fireOsActionHoldSteadyDetail;
    case FireActionKind.topUpCashBucket:
      final amount = action.amount;
      if (amount == null || action.months == null) return null;
      return l10n.fireOsActionTopUpCashBucketDetail(
        formatters.currency(amount.amount, code: amount.currency),
        action.months!,
      );
    case FireActionKind.reduceSpending:
      final pct = action.pct;
      if (pct == null) return l10n.fireOsActionReduceSpendingDetailGeneric;
      return l10n.fireOsActionReduceSpendingDetailPct(
        (pct * 100).toStringAsFixed(1),
      );
    case FireActionKind.delayDiscretionary:
      return l10n.fireOsActionDelayDiscretionaryDetail;
    case FireActionKind.rebalance:
      return l10n.fireOsActionRebalanceDetail;
    case FireActionKind.buildRiskReserve:
      return l10n.fireOsActionBuildRiskReserveDetail;
    case FireActionKind.runReview:
      return l10n.fireOsActionRunReviewDetail;
    case FireActionKind.fixCurrencyGap:
      if (action.months == null) return null;
      return l10n.fireOsActionFixCurrencyGapDetail(action.months!);
  }
}

String _safetyLabel(AppLocalizations l10n, FireSafetyLevel level) {
  switch (level) {
    case FireSafetyLevel.safe:
      return l10n.fireOsSafetySafe;
    case FireSafetyLevel.cautious:
      return l10n.fireOsSafetyCautious;
    case FireSafetyLevel.danger:
      return l10n.fireOsSafetyDanger;
    case FireSafetyLevel.unconfigured:
      return l10n.fireOsSafetyUnconfigured;
  }
}
