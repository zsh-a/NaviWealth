import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/event_timeline_providers.dart';
import '../domain/reporting/event_timeline.dart';

/// Embeddable "Upcoming events" section for the holding detail page
/// (`docs/roadmap-next.md` §3.5).
///
/// Reads [upcomingEventsForSymbolProvider] and renders a compact list of
/// the next 90 days of corporate actions for [symbol]. Falls back to a
/// quiet empty state when no events are scheduled — which is also the
/// state on platforms / before the yfinance fetcher is wired.
class EventTimelineSection extends ConsumerWidget {
  const EventTimelineSection({super.key, required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final eventsAsync = ref.watch(upcomingEventsForSymbolProvider(symbol));
    // Network fetcher is best-effort: loading + error both reduce to
    // the same empty placeholder so the holding detail page stays
    // calm during a transient outage.
    final events = eventsAsync.value ?? const <CorporateActionEvent>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: Text(
            l10n.investmentEventTimelineTitle,
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        if (events.isEmpty)
          SoftCard(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text(
              l10n.investmentEventTimelineEmpty,
              style: context.theme.typography.sm.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          )
        else
          for (final ev in events) ...[
            _EventRow(event: ev),
            const SizedBox(height: AppSpacing.s8),
          ],
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final CorporateActionEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final dateText = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).format(event.scheduledFor);
    return FCard.raw(
      child: FTile(
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            _kindIcon(event.kind),
            size: 18,
            color: colors.mutedForeground,
          ),
        ),
        title: Text(_kindLabel(l10n, event)),
        subtitle: Text(dateText),
        suffix: event.kind == CorporateActionKind.cashDividend
            ? MoneyText(
                amount: event.cashAmount.toDouble(),
                currencyCode: event.currency,
              )
            : null,
      ),
    );
  }
}

IconData _kindIcon(CorporateActionKind kind) => switch (kind) {
  CorporateActionKind.cashDividend => Icons.payments_outlined,
  CorporateActionKind.split => Icons.call_split,
  CorporateActionKind.rights => Icons.local_offer_outlined,
  CorporateActionKind.drip => Icons.refresh_outlined,
};

String _kindLabel(AppLocalizations l10n, CorporateActionEvent event) =>
    switch (event.kind) {
      CorporateActionKind.cashDividend => l10n.investmentEventDividend,
      CorporateActionKind.split => l10n.investmentEventSplit(
        event.ratio?.toString() ?? '',
      ),
      CorporateActionKind.rights => l10n.investmentEventRights,
      CorporateActionKind.drip => l10n.investmentEventDrip,
    };
