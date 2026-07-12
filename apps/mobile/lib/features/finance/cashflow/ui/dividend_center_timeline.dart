part of 'dividend_center_page.dart';

class _TimelineSection extends ConsumerStatefulWidget {
  const _TimelineSection({required this.snapshot});

  final DividendCenterSnapshot snapshot;

  @override
  ConsumerState<_TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends ConsumerState<_TimelineSection> {
  static const _initialMonthCount = 6;

  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final months = _showAll
        ? widget.snapshot.months
        : widget.snapshot.months.take(_initialMonthCount);
    final canToggle = widget.snapshot.months.length > _initialMonthCount;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(title: l10n.dividendCenterHistoryTimeline),
          const SizedBox(height: AppSpacing.s12),
          for (final month in months) ...[
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
                      net: formatters.currency(
                        event.grossInBase - event.withholdingInBase,
                        code: widget.snapshot.baseCurrency,
                      ),
                      gross: formatters.currency(
                        event.grossInBase,
                        code: widget.snapshot.baseCurrency,
                      ),
                      withholding: formatters.currency(
                        event.withholdingInBase,
                        code: widget.snapshot.baseCurrency,
                      ),
                      grossLabel: l10n.dividendCenterGross,
                      withholdingLabel: l10n.dividendCenterWithholding,
                      onTap: openMenu,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.s6),
          ],
          if (canToggle)
            FButton(
              variant: FButtonVariant.ghost,
              onPress: () => setState(() => _showAll = !_showAll),
              child: Text(
                _showAll
                    ? l10n.dividendCenterHistoryShowLess
                    : l10n.dividendCenterHistoryShowAll(
                        widget.snapshot.months.length,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.date,
    required this.asset,
    required this.net,
    required this.gross,
    required this.withholding,
    required this.grossLabel,
    required this.withholdingLabel,
    required this.onTap,
  });

  final String date;
  final String asset;
  final String net;
  final String gross;
  final String withholding;
  final String grossLabel;
  final String withholdingLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.theme.colors.mutedForeground;
    return FTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset,
                    style: context.labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    '$date · $grossLabel $gross · '
                    '$withholdingLabel $withholding',
                    style: context.captionStyle.copyWith(color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Text(net, style: TypographyTokens.numericBodyStrong),
            const SizedBox(width: AppSpacing.s6),
            Icon(
              FLucideIcons.ellipsisVertical,
              size: AppIconSizes.sm,
              color: muted,
            ),
          ],
        ),
      ),
    );
  }
}
