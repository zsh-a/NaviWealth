import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/entry_kind.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/posting.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/account_l10n.dart';
import 'activity_entry_detail_page.dart';

/// One row in the unified Activity timeline (iOS Wallet style).
///
/// Layout: rounded tinted icon disc · stacked title/subtitle · right-aligned
/// signed amount + time. Tapping pushes [ActivityEntryDetailPage] which
/// owns the full breakdown — no inline accordion expansion any more
/// (consistent with the calm-finance "row is the action target" rule).
class ActivityFeedEntryRow extends StatelessWidget {
  const ActivityFeedEntryRow({
    super.key,
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
    final timeStr = _formatTime(entry.entry.date);
    final iconData = _iconForKind(classification.kind);
    final iconTint = _tintForKind(classification.kind, colors);

    final subtitle = entry.entry.payee?.isNotEmpty == true
        ? entry.entry.payee!
        : _accountSummary(l10n, entry.postings, accountsById);

    return SoftCard(
      borderless: true,
      borderRadius: AppRadius.xlg,
      tinted: false,
      child: FTappable(
        onPress: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
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
                    color: iconTint.withValues(alpha: AppOpacity.prominent),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.entry.narration.isEmpty
                          ? '—'
                          : entry.entry.narration,
                      style: context.theme.typography.sm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        subtitle,
                        style: context.theme.typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
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
                        fontWeight: FontWeight.w700,
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

Color _tintForKind(EntryKind kind, FColors colors) {
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

String? _accountSummary(
  AppLocalizations l10n,
  List<Posting> postings,
  Map<String, Account> accounts,
) {
  for (final p in postings) {
    // Asset posting: show the symbol (e.g. "AAPL") instead of the
    // raw unit ID ("usStock:AAPL").
    if (p.unit.contains(':')) {
      return p.unit.substring(p.unit.indexOf(':') + 1);
    }
    final a = accounts[p.accountId];
    if (a != null) return localizedAccountName(l10n, a);
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
