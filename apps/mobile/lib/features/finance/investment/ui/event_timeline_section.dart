import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../data/event_timeline_providers.dart';
import '../domain/reporting/event_timeline.dart';

/// Embeddable "Upcoming events" section for the holding detail page
/// (`docs/roadmap-next.md` §3.5).
///
/// Reads [upcomingEventsForSymbolProvider] and renders a compact list of
/// the next 90 days of corporate actions for [symbol]. Falls back to a
/// quiet empty state when no events are scheduled, and a retryable error
/// state when the fetcher fails.
class EventTimelineSection extends ConsumerWidget {
  const EventTimelineSection({super.key, required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final eventsAsync = ref.watch(upcomingEventsForSymbolProvider(symbol));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: Text(
            l10n.investmentEventTimelineTitle,
            style: context.mutedLabelStyle,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        eventsAsync.when(
          loading: () => const SoftCard(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: SkeletonBox(height: AppSpacing.s40, radius: AppRadius.sm),
          ),
          error: (error, _) => AppEmptyState.error(
            title: l10n.investmentEventTimelineError,
            message: userSafeErrorMessage(context, error),
            retryLabel: l10n.commonRetry,
            onRetry: () {
              ref.invalidate(corporateActionEventsProvider(symbol));
              ref.invalidate(upcomingEventsForSymbolProvider(symbol));
            },
          ),
          data: (events) => events.isEmpty
              ? SoftCard(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Text(
                    l10n.investmentEventTimelineEmpty,
                    style: context.bodyCaptionStyle,
                  ),
                )
              : Column(
                  children: [
                    for (final ev in events) ...[
                      _EventRow(event: ev),
                      const SizedBox(height: AppSpacing.s8),
                    ],
                  ],
                ),
        ),
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
    return SoftCard(
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
            _kindIcon(event.kind),
            size: AppIconSizes.h18,
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
  CorporateActionKind.cashDividend => FLucideIcons.banknote,
  CorporateActionKind.split => FLucideIcons.gitBranch,
  CorporateActionKind.rights => FLucideIcons.tag,
  CorporateActionKind.drip => FLucideIcons.refreshCw,
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
