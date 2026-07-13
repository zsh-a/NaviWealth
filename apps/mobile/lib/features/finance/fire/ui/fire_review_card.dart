import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/haptics/haptics.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../data/fire_providers.dart';
import '../data/fire_review_cache.dart';
import '../domain/fire_review.dart';
import '../domain/fire_review_engine.dart';
import 'fire_status_colors.dart';

/// Periodic-review card.
///
/// Surfaces the deterministic monthly snapshot by default; a small
/// segmented row lets the user flip to quarterly / annual. "Save
/// snapshot" persists the current view into [fireReviewCacheProvider]
/// so the next period's review can diff against it (Phase 4 saves;
/// the diff readout itself is a Phase-4.1 follow-up).
class FireReviewCard extends ConsumerStatefulWidget {
  const FireReviewCard({super.key});

  @override
  ConsumerState<FireReviewCard> createState() => _FireReviewCardState();
}

class _FireReviewCardState extends ConsumerState<FireReviewCard> {
  FireReviewKind _kind = FireReviewKind.monthly;
  String? _savedKey;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    final liveAsync = ref.watch(fireLiveReviewProvider(_kind));

    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.fireOsReviewTitle, style: context.theme.typography.body.md),
          const SizedBox(height: AppSpacing.s4),
          Text(l10n.fireOsReviewSubtitle, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            children: [
              for (final kind in FireReviewKind.values)
                FButton(
                  variant: _kind == kind
                      ? FButtonVariant.primary
                      : FButtonVariant.outline,
                  onPress: () => setState(() {
                    _kind = kind;
                    _savedKey = null;
                  }),
                  child: Text(_kindLabel(l10n, kind)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          liveAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
              child: SizedBox.shrink(),
            ),
            error: (e, _) => Text(
              '$e',
              style: context.captionStyle.copyWith(
                color: context.theme.colors.destructive,
              ),
            ),
            data: (review) =>
                _ReviewBody(review: review, formatters: formatters, l10n: l10n),
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              FButton(
                variant: FButtonVariant.outline,
                onPress: _saving ? null : _save,
                prefix: const Icon(FLucideIcons.save, size: AppIconSizes.xs),
                child: Text(l10n.fireOsReviewSaveSnapshot),
              ),
              if (_savedKey != null) ...[
                const SizedBox(width: AppSpacing.s8),
                Text(
                  l10n.fireOsReviewSaved(_savedKey!),
                  style: context.captionStyle,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await saveLiveReview(ref, _kind);
      final review = ref
          .read(fireLiveReviewProvider(_kind))
          .maybeWhen(data: (r) => r, orElse: () => null);
      if (!mounted) return;
      Haptics.success();
      setState(() => _savedKey = review?.periodKey);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ReviewBody extends ConsumerWidget {
  const _ReviewBody({
    required this.review,
    required this.formatters,
    required this.l10n,
  });

  final FireReview review;
  final AppFormatters formatters;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final generated = review.generatedAt.toLocal().toIso8601String();
    final cache = ref.watch(fireReviewCacheProvider);
    final prior = _findPriorCached(cache, review.kind, review.periodKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${review.periodKey} · ${l10n.fireOsReviewGeneratedAt(generated)}',
          style: context.captionStyle,
        ),
        const SizedBox(height: AppSpacing.s8),
        _DiffPanel(
          diff: FireReviewDiff(before: prior, after: review),
          formatters: formatters,
          l10n: l10n,
        ),
        const SizedBox(height: AppSpacing.s12),
        Text(l10n.fireOsReviewFindingsTitle, style: context.labelStyle),
        const SizedBox(height: AppSpacing.s4),
        for (final f in review.findings) ...[
          _FindingRow(finding: f, formatters: formatters, l10n: l10n),
          const SizedBox(height: AppSpacing.s4),
        ],
      ],
    );
  }
}

class _DiffPanel extends StatelessWidget {
  const _DiffPanel({
    required this.diff,
    required this.formatters,
    required this.l10n,
  });

  final FireReviewDiff diff;
  final AppFormatters formatters;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final before = diff.before;
    if (before == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.s8),
        decoration: BoxDecoration(
          color: colors.muted.withValues(alpha: AppOpacity.muted),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          l10n.fireOsReviewDiffNoBaseline,
          style: context.captionStyle,
        ),
      );
    }
    final wrLine = _wrLine(l10n, diff);
    final nwLine = _netWorthLine(l10n, formatters, diff);
    final safetyLine = diff.safetyLevelChanged
        ? l10n.fireOsReviewDiffSafetyChanged(
            before.safetyLevel.name,
            diff.after.safetyLevel.name,
          )
        : l10n.fireOsReviewDiffSafetyHeld(diff.after.safetyLevel.name);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s10),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.muted),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.fireOsReviewDiffTitle(before.periodKey),
            style: context.captionLabelStyle.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            safetyLine,
            style: diff.safetyLevelChanged
                ? context.captionLabelStyle.copyWith(
                    color: fireSafetyColor(
                      SemanticColors.of(context),
                      diff.after.safetyLevel,
                    ),
                  )
                : context.captionStyle.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w400,
                  ),
          ),
          Text(wrLine, style: context.theme.typography.body.xs),
          Text(nwLine, style: context.theme.typography.body.xs),
        ],
      ),
    );
  }

  static String _wrLine(AppLocalizations l10n, FireReviewDiff diff) {
    final delta = diff.withdrawalRateDelta;
    if (delta == null) return l10n.fireOsReviewDiffWrUnavailable;
    final pp = delta * 100;
    final sign = pp == 0
        ? ''
        : pp > 0
        ? '+'
        : '−';
    return l10n.fireOsReviewDiffWr(sign, pp.abs().toStringAsFixed(2));
  }

  static String _netWorthLine(
    AppLocalizations l10n,
    AppFormatters formatters,
    FireReviewDiff diff,
  ) {
    final delta = diff.netWorthDelta;
    if (delta == null) return l10n.fireOsReviewDiffNetWorthCurrencyChanged;
    final sign = delta == Decimal.zero
        ? ''
        : delta > Decimal.zero
        ? '+'
        : '−';
    final abs = delta < Decimal.zero ? -delta : delta;
    return l10n.fireOsReviewDiffNetWorth(
      sign,
      formatters.currency(abs, code: diff.after.baseCurrency),
    );
  }
}

/// Find the most recent cached review of the same [kind] that doesn't
/// share [currentKey]. Returns null when the cache is empty or every
/// cached entry is for the current period.
FireReview? _findPriorCached(
  List<FireReview> cache,
  FireReviewKind kind,
  String currentKey,
) {
  for (final r in cache) {
    if (r.kind == kind && r.periodKey != currentKey) return r;
  }
  return null;
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({
    required this.finding,
    required this.formatters,
    required this.l10n,
  });

  final FireReviewFinding finding;
  final AppFormatters formatters;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final dotColor = fireActionSeverityColor(
      SemanticColors.of(context),
      finding.severity,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: AppSpacing.s6),
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            _findingText(l10n, finding),
            style: context.theme.typography.body.xs,
          ),
        ),
      ],
    );
  }
}

String _kindLabel(AppLocalizations l10n, FireReviewKind kind) {
  switch (kind) {
    case FireReviewKind.monthly:
      return l10n.fireOsReviewKindMonthly;
    case FireReviewKind.quarterly:
      return l10n.fireOsReviewKindQuarterly;
    case FireReviewKind.annual:
      return l10n.fireOsReviewKindAnnual;
  }
}

String _findingText(AppLocalizations l10n, FireReviewFinding f) {
  switch (f.code) {
    case FireReviewFindingCode.netWorthHealthy:
      return l10n.fireOsReviewFindingNetWorthHealthy;
    case FireReviewFindingCode.netWorthBroken:
      return l10n.fireOsReviewFindingNetWorthBroken;
    case FireReviewFindingCode.withdrawalRateBelowSwr:
      return l10n.fireOsReviewFindingWithdrawalRateBelowSwr(
        ((f.pct ?? 0) * 100).toStringAsFixed(1),
      );
    case FireReviewFindingCode.withdrawalRateAboveSwr:
      return l10n.fireOsReviewFindingWithdrawalRateAboveSwr(
        ((f.pct ?? 0) * 100).toStringAsFixed(1),
      );
    case FireReviewFindingCode.withdrawalRateInfinite:
      return l10n.fireOsReviewFindingWithdrawalRateInfinite;
    case FireReviewFindingCode.withinTargetCashBucket:
      return l10n.fireOsReviewFindingWithinTargetCashBucket(f.months ?? 0);
    case FireReviewFindingCode.belowTargetCashBucket:
      return l10n.fireOsReviewFindingBelowTargetCashBucket(f.months ?? 0);
    case FireReviewFindingCode.fireEtaReached:
      return l10n.fireOsReviewFindingFireEtaReached;
    case FireReviewFindingCode.fireEtaUnreachable:
      return l10n.fireOsReviewFindingFireEtaUnreachable;
    case FireReviewFindingCode.fireEtaProgressing:
      return l10n.fireOsReviewFindingFireEtaProgressing(f.months ?? 0);
    case FireReviewFindingCode.currencyGapPresent:
      return l10n.fireOsReviewFindingCurrencyGap(f.months ?? 0);
    case FireReviewFindingCode.unmappedHoldingsPresent:
      return l10n.fireOsReviewFindingUnmappedHoldings(f.months ?? 0);
    case FireReviewFindingCode.stressTestDanger:
      return l10n.fireOsReviewFindingStressDanger(f.scenarioCode ?? 'unknown');
    case FireReviewFindingCode.stressTestCautious:
      return l10n.fireOsReviewFindingStressCautious(
        f.scenarioCode ?? 'unknown',
      );
    case FireReviewFindingCode.stressTestSafe:
      return l10n.fireOsReviewFindingStressSafe;
  }
}
