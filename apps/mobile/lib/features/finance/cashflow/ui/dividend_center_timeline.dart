part of 'dividend_center_page.dart';

class _TimelineSection extends ConsumerWidget {
  const _TimelineSection({required this.snapshot});

  final DividendCenterSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(title: l10n.dividendCenterHistoryTimeline),
          const SizedBox(height: AppSpacing.s12),
          for (final month in snapshot.months) ...[
            Text(formatters.monthYear(month.month), style: context.labelStyle),
            const SizedBox(height: AppSpacing.s8),
            for (final event in month.events)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                child: AppAdaptiveActionMenu(
                  title: l10n.dividendEventActionsTitle,
                  subtitle:
                      '${event.assetLabel} · '
                      '${formatters.date(event.event.date)}',
                  actions: buildDividendEventActions(context, ref, event),
                  triggerBuilder: (context, openMenu, focusNode) => Focus(
                    focusNode: focusNode,
                    child: _TimelineRow(
                      date: formatters.date(event.event.date),
                      asset: event.assetLabel,
                      gross: formatters.currency(
                        event.grossInBase,
                        code: snapshot.baseCurrency,
                      ),
                      withholding: formatters.currency(
                        event.withholdingInBase,
                        code: snapshot.baseCurrency,
                      ),
                      onTap: openMenu,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.s6),
          ],
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.date,
    required this.asset,
    required this.gross,
    required this.withholding,
    required this.onTap,
  });

  final String date;
  final String asset;
  final String gross;
  final String withholding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.theme.colors.mutedForeground;
    return FTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Row(
          children: [
            Text(
              date,
              style: context.theme.typography.body.sm.copyWith(color: muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(asset, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: AppSpacing.s12),
            Flexible(
              child: Text(
                gross,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Flexible(
              child: Text(
                withholding,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.theme.typography.body.sm.copyWith(color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
