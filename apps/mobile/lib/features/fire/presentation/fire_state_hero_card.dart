import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/intent/ai_intent_invocation.dart';
import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ai_chat/ui/ai_hover_overlay.dart';
import '../../ai_chat/ui/ask_ai.dart';
import '../data/fire_providers.dart';
import '../domain/fire_action.dart';
import '../domain/fire_state.dart';
import 'fire_ai_capsule.dart';
import 'fire_status_colors.dart';

/// "自由状态" hero card — the headline of the FIRE OS page.
///
/// Composes the safety pill, the four core metrics (WR, cash bucket, FIRE
/// ETA, net worth), and the top suggested next steps. Pure read — saves
/// nothing, mutates nothing. On device builds where the AI runtime is
/// usable the "Explain" pill opens a contextual bottom sheet wired to
/// the `explain_fire_state` intent; web (no on-device AI) hides it.
class FireStateHeroCard extends ConsumerWidget {
  const FireStateHeroCard({super.key});

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
      data: (state) => _HeroBody(l10n: l10n, state: state, onExplain: explain),
    );
  }
}

class _HeroBody extends ConsumerWidget {
  const _HeroBody({
    required this.l10n,
    required this.state,
    required this.onExplain,
  });

  final AppLocalizations l10n;
  final FireState state;
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

    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.fireOsHeroTitle,
                      style: context.theme.typography.md,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(l10n.fireOsHeroSubtitle, style: context.captionStyle),
                  ],
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
          const SizedBox(height: AppSpacing.s16),
          _MetricsGrid(state: state, formatters: formatters, l10n: l10n),
          const SizedBox(height: AppSpacing.s12),
          _SuggestedActions(state: state, formatters: formatters, l10n: l10n),
          if (onExplain != null) ...[
            const SizedBox(height: AppSpacing.s12),
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
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.state,
    required this.formatters,
    required this.l10n,
  });

  final FireState state;
  final AppFormatters formatters;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final swrPct = (state.plan.safeWithdrawalRate * 100).toStringAsFixed(1);
    final wrLabel = state.withdrawalRate.isFinite
        ? l10n.fireOsHeroWithdrawalRateValue(
            (state.withdrawalRate * 100).toStringAsFixed(2),
            swrPct,
          )
        : l10n.fireOsHeroWithdrawalRateInfinite;

    final cashLabel = state.cashBucketMonths.isFinite
        ? l10n.fireOsHeroCashBucketValue(
            state.cashBucketMonths.toStringAsFixed(1),
            state.plan.targetCashBucketMonths,
          )
        : (state.cashBucketMonths == 0
              ? l10n.fireOsHeroCashBucketInfinite
              : l10n.fireOsHeroCashBucketInfinite);

    final etaLabel = _etaLabel(l10n, state.fireEtaMonths);
    final netWorth = formatters.currency(
      state.netWorth.amount,
      code: state.baseCurrency,
    );
    final annualSpend = formatters.currency(
      state.annualSpend.amount,
      code: state.baseCurrency,
    );
    final spendSourceLabel =
        state.annualSpendSource == FireAnnualSpendSource.trailing12m
        ? l10n.fireOsAnnualSpendSourceTrailing
        : l10n.fireOsAnnualSpendSourcePlan;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: l10n.fireOsHeroWithdrawalRateLabel,
                value: wrLabel,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _MetricTile(
                label: l10n.fireOsHeroCashBucketLabel,
                value: cashLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: l10n.fireOsHeroEtaLabel,
                value: etaLabel,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _MetricTile(
                label: l10n.fireOsHeroNetWorthLabel,
                value: netWorth,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: l10n.fireOsHeroAnnualSpendLabel,
                value: '$annualSpend · $spendSourceLabel',
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _etaLabel(AppLocalizations l10n, int? months) {
    if (months == null) return l10n.fireOsHeroEtaUnreachable;
    if (months == 0) return l10n.fireOsHeroEtaReached;
    final years = months ~/ 12;
    final m = months % 12;
    if (years == 0) return l10n.fireCountdownMonthsOnly(m);
    if (m == 0) return l10n.fireCountdownYearsOnly(years);
    return l10n.fireCountdownYearsMonths(years, m);
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.muted),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(
            value,
            style: context.labelStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SuggestedActions extends StatelessWidget {
  const _SuggestedActions({
    required this.state,
    required this.formatters,
    required this.l10n,
  });

  final FireState state;
  final AppFormatters formatters;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (state.suggestedActions.isEmpty) return const SizedBox.shrink();
    return AiHoverOverlay(
      topOffset: 0,
      endOffset: 0,
      capsule: FireAiCapsule(
        intent: 'suggest_fire_actions',
        source: 'fire_os_hero_actions',
        objectLabel: l10n.fireOsSuggestedActionsTitle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.fireOsSuggestedActionsTitle,
            style: context.bodyCaptionStyle,
          ),
          const SizedBox(height: AppSpacing.s6),
          for (final action in state.suggestedActions.take(3)) ...[
            _ActionRow(action: action, formatters: formatters, l10n: l10n),
            const SizedBox(height: AppSpacing.s6),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
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
              Text(title, style: context.theme.typography.sm),
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
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 120, height: 18, color: context.theme.colors.muted),
          const SizedBox(height: AppSpacing.s16),
          Container(
            width: double.infinity,
            height: 64,
            color: context.theme.colors.muted,
          ),
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
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
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

/// Localise [FireAction.kind] → headline. Public so other surfaces
/// (Phase 5 AI explain sheet, home insights) share the same copy.
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

/// Localise the structured params on a [FireAction] into a short detail
/// sentence. Returns `null` when there's no param payload — the title
/// alone is enough.
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
