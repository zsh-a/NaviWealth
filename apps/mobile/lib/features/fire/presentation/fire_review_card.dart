import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../core/haptics/haptics.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/fire_providers.dart';
import '../domain/fire_action.dart';
import '../domain/fire_review.dart';

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

    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.fireOsReviewTitle, style: context.theme.typography.md),
            const SizedBox(height: 4),
            Text(
              l10n.fireOsReviewSubtitle,
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
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
            const SizedBox(height: 12),
            liveAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox.shrink(),
              ),
              error: (e, _) => Text(
                '$e',
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.destructive,
                ),
              ),
              data: (review) => _ReviewBody(
                review: review,
                formatters: formatters,
                l10n: l10n,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: _saving ? null : _save,
                  prefix: const Icon(Icons.save_outlined, size: 14),
                  child: Text(l10n.fireOsReviewSaveSnapshot),
                ),
                if (_savedKey != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    l10n.fireOsReviewSaved(_savedKey!),
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await saveLiveReview(ref, _kind);
      final review = ref.read(fireLiveReviewProvider(_kind)).maybeWhen(
            data: (r) => r,
            orElse: () => null,
          );
      if (!mounted) return;
      Haptics.success();
      setState(() => _savedKey = review?.periodKey);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ReviewBody extends StatelessWidget {
  const _ReviewBody({
    required this.review,
    required this.formatters,
    required this.l10n,
  });

  final FireReview review;
  final AppFormatters formatters;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final generated = review.generatedAt.toLocal().toIso8601String();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${review.periodKey} · ${l10n.fireOsReviewGeneratedAt(generated)}',
          style: context.theme.typography.xs.copyWith(
            color: colors.mutedForeground,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.fireOsReviewFindingsTitle,
          style: context.theme.typography.sm.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        for (final f in review.findings) ...[
          _FindingRow(finding: f, formatters: formatters, l10n: l10n),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
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
    final colors = context.theme.colors;
    final dotColor = _severityColor(colors, finding.severity);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _findingText(l10n, finding),
            style: context.theme.typography.xs,
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
      return l10n.fireOsReviewFindingStressDanger(
        f.scenarioCode ?? 'unknown',
      );
    case FireReviewFindingCode.stressTestCautious:
      return l10n.fireOsReviewFindingStressCautious(
        f.scenarioCode ?? 'unknown',
      );
    case FireReviewFindingCode.stressTestSafe:
      return l10n.fireOsReviewFindingStressSafe;
  }
}

Color _severityColor(FColors colors, FireActionSeverity severity) {
  switch (severity) {
    case FireActionSeverity.info:
      return colors.mutedForeground;
    case FireActionSeverity.warning:
      return Colors.amber.shade700;
    case FireActionSeverity.critical:
      return colors.destructive;
  }
}
