import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/entry_kind.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/posting.dart';
import '../../../data/repositories/journal_entry_repository.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../activity/data/activity_feed_provider.dart';

/// Last `kHomeActivityPreviewCount` journal entries, rendered iOS Wallet
/// style: rounded icon + double-line label + right-aligned amount.
///
/// Tapping any row pushes the user into the full activity timeline; the
/// preview is read-only — full filtering / detail flows happen on the
/// dedicated /activity surface.
const int kHomeActivityPreviewCount = 5;

class ActivityTimelinePreview extends ConsumerWidget {
  const ActivityTimelinePreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatter = context.formatters(ref);
    final feedAsync = ref.watch(activityFeedProvider);
    return feedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (page) {
        if (page.entries.isEmpty) return const SizedBox.shrink();
        final entries = page.entries.take(kHomeActivityPreviewCount).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.dashboardActivityPreviewTitle,
                      style: context.theme.typography.sm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                  ),
                  FTappable(
                    onPress: () => context.go(AppRoutes.activity),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        l10n.dashboardActivityPreviewViewAll,
                        style: context.theme.typography.xs.copyWith(
                          color: context.theme.colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SoftCard(
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    _PreviewRow(
                      entry: entries[i],
                      accountsById: page.accountsById,
                      formatter: formatter,
                    ),
                    if (i < entries.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          height: 1,
                          color: context.theme.colors.foreground.withValues(
                            alpha: 0.06,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.entry,
    required this.accountsById,
    required this.formatter,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
  final AppFormatters formatter;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final headline = _headlinePosting(entry.postings, accountsById);
    final timeStr = _formatTime(entry.entry.date);
    final iconData = _iconForKind(classification.kind);
    final iconColor = _colorForKind(classification.kind, colors);

    return FTappable(
      onPress: () => context.go(AppRoutes.activity),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(iconData, size: 16, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.entry.narration.isEmpty ? '—' : entry.entry.narration,
                    style: context.theme.typography.sm.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.entry.payee != null &&
                      entry.entry.payee!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        entry.entry.payee!,
                        style: context.theme.typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (headline != null)
                  SignedMoneyText(
                    amount: headline.units,
                    unit: headline.unit,
                    formatters: formatter,
                    style: context.theme.typography.sm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  timeStr,
                  style: context.theme.typography.xs.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconForKind(EntryKind kind) {
  switch (kind) {
    case EntryKind.income:
      return Icons.south_west_outlined;
    case EntryKind.expense:
      return Icons.shopping_bag_outlined;
    case EntryKind.payment:
      return Icons.payments_outlined;
    case EntryKind.transfer:
      return Icons.swap_horiz_outlined;
    case EntryKind.trade:
      return Icons.show_chart_outlined;
    case EntryKind.adjustment:
      return Icons.tune_outlined;
    case EntryKind.opening:
      return Icons.flag_outlined;
    case EntryKind.other:
      return Icons.receipt_long_outlined;
  }
}

Color _colorForKind(EntryKind kind, FColors colors) {
  switch (kind) {
    case EntryKind.income:
    case EntryKind.trade:
      return colors.primary;
    case EntryKind.expense:
    case EntryKind.payment:
    case EntryKind.transfer:
    case EntryKind.adjustment:
    case EntryKind.opening:
    case EntryKind.other:
      return colors.mutedForeground;
  }
}

String _formatTime(DateTime date) {
  final h = date.hour.toString().padLeft(2, '0');
  final m = date.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

Posting? _headlinePosting(
  List<Posting> postings,
  Map<String, Account> accounts,
) {
  Posting? headline;
  Decimal? best;
  for (final p in postings) {
    final account = accounts[p.accountId];
    if (account == null) continue;
    if (account.category != AccountSide.asset &&
        account.category != AccountSide.liability) {
      continue;
    }
    final magnitude = p.units.abs();
    if (best == null || magnitude > best) {
      best = magnitude;
      headline = p;
    }
  }
  return headline;
}
