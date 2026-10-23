import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../format/formatters.dart';
import '../action_outcome.dart';

/// One presentation for source observations at the source, detail, and review.
/// Completion is shown by the host; this view never treats it as clearance.
class ActionOutcomeView extends StatelessWidget {
  const ActionOutcomeView({
    super.key,
    required this.outcome,
    this.onRefresh,
    this.onReview,
  });

  final AsyncValue<ActionOutcomeSummary?> outcome;
  final VoidCallback? onRefresh;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = outcome.asData?.value;
    final status = outcome.hasError
        ? ActionOutcomeStatus.failed
        : outcome.isLoading
        ? ActionOutcomeStatus.pending
        : summary?.status ?? ActionOutcomeStatus.unsupported;
    final label = !outcome.hasError && !outcome.isLoading && summary == null
        ? l10n.actionOutcomeUnavailable
        : switch (status) {
            ActionOutcomeStatus.signalCleared =>
              l10n.executionOutcomeSignalCleared(summary!.sourceLabel),
            ActionOutcomeStatus.signalStillActive =>
              l10n.executionOutcomeSignalStillActive(summary!.sourceLabel),
            ActionOutcomeStatus.pending => l10n.actionOutcomePending,
            ActionOutcomeStatus.incomplete => l10n.actionOutcomeIncomplete,
            ActionOutcomeStatus.failed => l10n.actionOutcomeFailed,
            ActionOutcomeStatus.unsupported => l10n.actionOutcomeUnsupported,
          };
    final evaluatedAt = summary?.evaluatedAt;
    final refresh =
        summary?.isObserved != true && status != ActionOutcomeStatus.unsupported
        ? onRefresh
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.labelStyle),
        if (summary?.isObserved == true && evaluatedAt != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.actionOutcomeObservedAt(
              AppFormatters(locale: Localizations.localeOf(context))
                  .dateTime(evaluatedAt.toLocal()),
            ),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(l10n.actionOutcomeObservational, style: context.captionStyle),
        ],
        if (refresh != null || onReview != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s4,
            children: [
              if (refresh != null)
                AppQuietButton(
                  label: status == ActionOutcomeStatus.failed
                      ? l10n.commonRetry
                      : l10n.actionOutcomeRefresh,
                  onPress: refresh,
                ),
              if (onReview != null)
                AppQuietButton(
                  label: l10n.actionOutcomeReview,
                  onPress: onReview,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
