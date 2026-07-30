import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';

import '../../../../core/format/formatters.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../shared/l10n/account_l10n.dart';
import '../../shared/l10n/entry_kind_labels.dart';
import 'activity_entry_detail_page.dart';
import 'activity_feed_grouping.dart';

/// One row in the unified Activity timeline.
///
/// Layout: tinted icon disc · title/subtitle · signed amount + time.
/// Tap opens [ActivityEntryDetailPage].
class ActivityFeedEntryRow extends StatelessWidget {
  const ActivityFeedEntryRow({
    super.key,
    required this.entry,
    required this.accountsById,
    required this.formatter,
    this.compact = false,
    this.showTime = true,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
  final AppFormatters formatter;

  /// Tighter padding for home preview.
  final bool compact;

  /// Journal-style surfaces already group rows by date and can omit the
  /// redundant time line while keeping the same row hierarchy.
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final status = context.appTheme.status;
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final headline = activityHeadlinePosting(entry.postings, accountsById);
    final title = entry.entry.narration.isEmpty ? '—' : entry.entry.narration;
    final subtitle = activityRowSubtitle(
      l10n: l10n,
      entry: entry,
      accountsById: accountsById,
      kind: classification.kind,
    );
    final timeStr = formatter.time(entry.entry.date);
    final iconTint = activityKindTint(classification.kind, colors, status);
    final iconData = activityKindIcon(classification.kind);
    final padH = compact ? AppSpacing.s14 : AppSpacing.s12;
    final padV = compact ? AppSpacing.s10 : AppSpacing.s12;

    return AppTappable(
      onPress: () => _openDetail(context),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        child: Row(
          children: [
            _KindDisc(icon: iconData, tint: iconTint),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: compact
                        ? context.mediumLabelStyle
                        : context.labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      subtitle,
                      style: context.captionStyle,
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
                    style: compact
                        ? context.labelStyle
                        : context.strongLabelStyle,
                  ),
                if (showTime) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(timeStr, style: context.captionStyle),
                ],
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
        FinanceRouteNames.activityEntryDetail,
        pathParameters: {'entryId': entry.entry.id},
        extra: args,
      );
      return;
    }

    Navigator.of(context).push<void>(
      buildAppPageRoute<void>(
        context: context,
        pageBuilder: (_, _, _) => ActivityEntryDetailPage(
          entry: args.entry,
          accountsById: args.accountsById,
        ),
      ),
    );
  }
}

/// Grouped-surface chrome shared by Activity and raw journal timelines.
///
/// Adjacent rows stitch into one neutral surface; callers keep each entry as
/// a top-level sliver/list item so large trading days remain virtualized.
class ActivityFeedEntrySurface extends StatelessWidget {
  const ActivityFeedEntrySurface({
    super.key,
    required this.entry,
    required this.accountsById,
    required this.formatter,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    this.showTime = true,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
  final AppFormatters formatter;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.vertical(
      top: isFirstInGroup ? const Radius.circular(AppRadius.lg) : Radius.zero,
      bottom: isLastInGroup ? const Radius.circular(AppRadius.lg) : Radius.zero,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: appGroupedSurfaceFill(context),
        borderRadius: radius,
      ),
      child: Column(
        children: [
          ActivityFeedEntryRow(
            entry: entry,
            accountsById: accountsById,
            formatter: formatter,
            showTime: showTime,
          ),
          if (!isLastInGroup) const AppGroupedDivider(indent: AppSpacing.s56),
        ],
      ),
    );
  }
}

class _KindDisc extends StatelessWidget {
  const _KindDisc({required this.icon, required this.tint});

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.s32,
      height: AppSpacing.s32,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: AppOpacity.light),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: AppIconSizes.sm, color: tint),
    );
  }
}

/// Subtitle: prefer payee · account path; transfers show A → B when possible.
String? activityRowSubtitle({
  required AppLocalizations l10n,
  required JournalEntryWithPostings entry,
  required Map<String, Account> accountsById,
  required EntryKind kind,
}) {
  if (kind == EntryKind.transfer) {
    final ends = _transferEnds(entry.postings, accountsById, l10n);
    if (ends != null) return ends;
  }
  if (kind == EntryKind.trade) {
    final symbol = _firstAssetSymbol(entry.postings);
    final cash = _firstCashAccountName(entry.postings, accountsById, l10n);
    if (symbol != null && cash != null) return '$symbol · $cash';
    if (symbol != null) return symbol;
  }

  final parts = <String>[];
  final payee = entry.entry.payee;
  if (payee != null && payee.isNotEmpty) parts.add(payee);

  final account = _primaryAccountLabel(entry.postings, accountsById, l10n);
  if (account != null && !parts.contains(account)) parts.add(account);

  if (parts.isEmpty) {
    final kindLabel = entryKindLabel(l10n, kind);
    return kindLabel;
  }
  return parts.join(' · ');
}

String? _transferEnds(
  List<Posting> postings,
  Map<String, Account> accounts,
  AppLocalizations l10n,
) {
  String? from;
  String? to;
  for (final p in postings) {
    final a = accounts[p.accountId];
    if (a == null || a.category != AccountSide.asset) continue;
    final name = localizedAccountName(l10n, a);
    if (p.units < Decimal.zero) {
      from ??= name;
    } else if (p.units > Decimal.zero) {
      to ??= name;
    }
  }
  if (from != null && to != null) return '$from → $to';
  return from ?? to;
}

String? _firstAssetSymbol(List<Posting> postings) {
  for (final p in postings) {
    if (p.unit.contains(':')) {
      return p.unit.substring(p.unit.indexOf(':') + 1);
    }
  }
  return null;
}

String? _firstCashAccountName(
  List<Posting> postings,
  Map<String, Account> accounts,
  AppLocalizations l10n,
) {
  for (final p in postings) {
    if (p.unit.contains(':')) continue;
    final a = accounts[p.accountId];
    if (a != null && a.category == AccountSide.asset) {
      return localizedAccountName(l10n, a);
    }
  }
  return null;
}

String? _primaryAccountLabel(
  List<Posting> postings,
  Map<String, Account> accounts,
  AppLocalizations l10n,
) {
  // Prefer expense/income category account names for daily spend readability.
  for (final side in const [
    AccountSide.expense,
    AccountSide.income,
    AccountSide.asset,
    AccountSide.liability,
  ]) {
    for (final p in postings) {
      final a = accounts[p.accountId];
      if (a == null || a.category != side) continue;
      if (p.unit.contains(':')) {
        return p.unit.substring(p.unit.indexOf(':') + 1);
      }
      return localizedAccountName(l10n, a);
    }
  }
  return null;
}

IconData activityKindIcon(EntryKind kind) {
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

Color activityKindTint(EntryKind kind, FColors colors, AppStatus status) {
  switch (kind) {
    case EntryKind.income:
      return status.success.fg;
    case EntryKind.trade:
      return colors.primary;
    case EntryKind.expense:
    case EntryKind.payment:
      return status.danger.fg;
    case EntryKind.transfer:
      return status.info.fg;
    case EntryKind.adjustment:
      return status.warning.fg;
    case EntryKind.opening:
    case EntryKind.other:
      return colors.mutedForeground;
  }
}
