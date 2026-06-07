import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/entry_kind.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/posting.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
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
              padding: const EdgeInsets.only(
                left: AppSpacing.s4,
                top: AppSpacing.s4,
                bottom: AppSpacing.s8,
              ),
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
                        horizontal: AppSpacing.s4,
                        vertical: AppSpacing.s2,
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
              borderless: true,
              tinted: false,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s12,
                        ),
                        child: Container(
                          height: 1,
                          color: context.theme.colors.foreground.withValues(
                            alpha: AppOpacity.faint,
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: AppSpacing.s10,
        ),
        child: Row(
          children: [
            SizedBox(
              width: AppSpacing.s32,
              height: AppSpacing.s32,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Icon(
                  iconData,
                  size: AppIconSizes.md,
                  color: iconColor.withValues(alpha: AppOpacity.prominent),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
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
                      padding: const EdgeInsets.only(top: AppSpacing.s2),
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
            const SizedBox(width: AppSpacing.s8),
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
                const SizedBox(height: AppSpacing.s2),
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
      return FLucideIcons.arrowDownLeft;
    case EntryKind.expense:
      return FLucideIcons.shoppingBag;
    case EntryKind.payment:
      return FLucideIcons.banknote;
    case EntryKind.transfer:
      return FLucideIcons.arrowLeftRight;
    case EntryKind.trade:
      return FLucideIcons.chartLine;
    case EntryKind.adjustment:
      return FLucideIcons.slidersHorizontal;
    case EntryKind.opening:
      return FLucideIcons.flag;
    case EntryKind.other:
      return FLucideIcons.receipt;
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
