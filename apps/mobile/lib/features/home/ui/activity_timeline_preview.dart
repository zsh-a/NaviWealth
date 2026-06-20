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
import '../../activity/ui/activity_entry_detail_page.dart';
import '../../shared/account_l10n.dart';

/// Last `kHomeActivityPreviewCount` journal entries, rendered iOS Wallet
/// style: rounded icon + double-line label + right-aligned amount.
///
/// Tapping the header action opens the full activity timeline; tapping a row
/// opens that entry's detail surface.
const int kHomeActivityPreviewCount = 5;

class ActivityTimelinePreview extends ConsumerWidget {
  const ActivityTimelinePreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = context.formatters(ref);
    final feedAsync = ref.watch(activityFeedProvider);
    return feedAsync.when(
      loading: () =>
          const _ActivityPreviewSection(child: _ActivityPreviewSkeleton()),
      error: (e, _) => _ActivityPreviewSection(
        child: _ActivityPreviewError(
          onRetry: () => ref.invalidate(activityFeedProvider),
        ),
      ),
      data: (page) {
        if (page.entries.isEmpty) return const SizedBox.shrink();
        final entries = page.entries.take(kHomeActivityPreviewCount).toList();
        return _ActivityPreviewSection(
          child: SoftCard(
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
        );
      },
    );
  }
}

class _ActivityPreviewSection extends StatelessWidget {
  const _ActivityPreviewSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                  style: context.mutedLabelStyle,
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
                    style: context.captionLabelStyle.copyWith(
                      color: context.theme.colors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class _ActivityPreviewSkeleton extends StatelessWidget {
  const _ActivityPreviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      borderless: true,
      tinted: false,
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      child: Column(
        children: [
          _SkeletonRow(),
          SizedBox(height: AppSpacing.s12),
          _SkeletonRow(),
          SizedBox(height: AppSpacing.s12),
          _SkeletonRow(),
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SkeletonBox(width: AppSpacing.s32, height: AppSpacing.s32, radius: 8),
        SizedBox(width: AppSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 132, height: 14, radius: 5),
              SizedBox(height: AppSpacing.s6),
              SkeletonBox(width: 88, height: 12, radius: 5),
            ],
          ),
        ),
        SizedBox(width: AppSpacing.s12),
        SkeletonBox(width: 64, height: 16, radius: 5),
      ],
    );
  }
}

class _ActivityPreviewError extends StatelessWidget {
  const _ActivityPreviewError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      borderless: true,
      tinted: false,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(l10n.commonLoadFailed, style: context.bodyCaptionStyle),
          ),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: onRetry,
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
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
    final l10n = AppLocalizations.of(context);
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final headline = _headlinePosting(entry.postings, accountsById);
    final subtitle = _previewSubtitle(l10n, entry, accountsById);
    final timeStr = _formatTimestamp(entry.entry.date, formatter);
    final iconData = _iconForKind(classification.kind);
    final iconColor = _colorForKind(classification.kind, colors);

    return FTappable(
      onPress: () => _openDetail(context),
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
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s2),
                      child: Text(
                        subtitle,
                        style: context.captionStyle,
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
                    style: context.labelStyle,
                  ),
                const SizedBox(height: AppSpacing.s2),
                Text(timeStr, style: context.captionStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    final args = ActivityEntryDetailArgs(
      entry: entry,
      accountsById: accountsById,
    );
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      context.pushNamed(
        AppRouteNames.activityEntryDetail,
        pathParameters: {'entryId': entry.entry.id},
        extra: args,
      );
      return;
    }

    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => ActivityEntryDetailPage(
          entry: args.entry,
          accountsById: args.accountsById,
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

String _formatTimestamp(DateTime date, AppFormatters formatter) {
  final local = date.toLocal();
  final now = DateTime.now();
  if (_sameLocalDay(local, now)) return formatter.time(local);
  return formatter.monthDay(local);
}

bool _sameLocalDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String? _previewSubtitle(
  AppLocalizations l10n,
  JournalEntryWithPostings entry,
  Map<String, Account> accounts,
) {
  final payee = entry.entry.payee;
  if (payee != null && payee.isNotEmpty) return payee;
  for (final p in entry.postings) {
    if (p.unit.contains(':')) {
      return p.unit.substring(p.unit.indexOf(':') + 1);
    }
    final account = accounts[p.accountId];
    if (account != null) return localizedAccountName(l10n, account);
  }
  return null;
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
