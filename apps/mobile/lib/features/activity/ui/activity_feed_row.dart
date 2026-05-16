import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/formatters.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/entry_kind.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/posting.dart';
import '../../../data/repositories/journal_entry_repository.dart';
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
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final summary = _summariseAmount(entry.postings, accountsById);
    final timeStr = _formatTime(entry.entry.date);
    final iconData = _iconForKind(classification.kind);
    final iconTint = _tintForKind(classification.kind, colors);

    final subtitle = entry.entry.payee?.isNotEmpty == true
        ? entry.entry.payee!
        : _accountSummary(entry.postings, accountsById);

    return FCard.raw(
      child: FTile(
        onPress: () => _openDetail(context),
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconTint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(iconData, size: 18, color: iconTint),
        ),
        title: Text(
          entry.entry.narration.isEmpty ? '—' : entry.entry.narration,
          style: context.theme.typography.sm.copyWith(
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: context.theme.typography.xs.copyWith(
                  color: colors.mutedForeground,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        suffix: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (summary != null)
              Text(
                summary,
                style: context.theme.typography.sm.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
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

String? _accountSummary(List<Posting> postings, Map<String, Account> accounts) {
  for (final p in postings) {
    final a = accounts[p.accountId];
    if (a != null) return a.name;
  }
  return null;
}

String? _summariseAmount(
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
  if (headline == null) return null;
  final value = headline.units;
  return '${value > Decimal.zero ? '+' : ''}${_formatDecimal(value)} ${headline.unit}';
}

String _formatDecimal(Decimal d) {
  if (d == Decimal.zero) return '0';
  final s = d.toString();
  if (!s.contains('.')) return s;
  final trimmed = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}
