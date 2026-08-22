part of '../rebalance_execution_workspace_page.dart';

class _ExecutionProgress extends StatelessWidget {
  const _ExecutionProgress({
    super.key,
    required this.resolved,
    required this.total,
    required this.driftAfterPct,
  });

  final int resolved;
  final int total;
  final double driftAfterPct;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    return SoftCard.raised(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceExecutionProgress(resolved, total),
                    style: context.theme.typography.body.sm,
                  ),
                ),
                Text(
                  formatters.percent(driftAfterPct, decimalDigits: 1),
                  style: context.captionLabelStyle,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            LinearProgressIndicator(value: total == 0 ? 0 : resolved / total),
          ],
        ),
      ),
    );
  }
}
