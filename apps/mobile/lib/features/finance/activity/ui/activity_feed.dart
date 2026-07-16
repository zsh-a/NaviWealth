import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/shell/shell_chrome.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/activity_feed_provider.dart';
import 'activity_action_panel.dart';
import 'activity_feed_filter_sheet.dart';
import 'activity_feed_grouping.dart';
import 'activity_feed_row.dart';

/// Timeline feed grouped by calendar day with day totals and infinite scroll.
class ActivityFeed extends ConsumerWidget {
  const ActivityFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final feedAsync = ref.watch(activityFeedProvider);

    return feedAsync.when(
      data: (page) {
        if (page.entries.isEmpty) {
          return _RefreshableFeed(
            onRefresh: () async {
              ref.invalidate(activityFeedProvider);
              await ref.read(activityFeedProvider.future);
            },
            child: _EmptyFeed(
              message: page.isFiltered
                  ? l10n.activityFeedFilteredEmpty
                  : l10n.activityFeedEmpty,
              actionLabel: page.isFiltered
                  ? l10n.activityFeedFilterTitle
                  : l10n.activityAddAction,
              onAction: page.isFiltered
                  ? () => ActivityFeedFilterSheet.show(context)
                  : () => showActivityActionPanel(context),
              filtered: page.isFiltered,
            ),
          );
        }
        final groups = groupActivityEntriesByDay(
          page.entries,
          accountsById: page.accountsById,
        );
        final totals = ActivityPageTotals.fromEntries(
          page.entries,
          accountsById: page.accountsById,
        );
        final formatter = AppFormatters(
          locale: Localizations.localeOf(context),
        );
        return _RefreshableFeed(
          onRefresh: () async {
            ref.invalidate(activityFeedProvider);
            await ref.read(activityFeedProvider.future);
          },
          child: _FeedList(
            groups: groups,
            pageTotals: totals,
            accountsById: page.accountsById,
            formatter: formatter,
            l10n: l10n,
            hasMore: page.hasMore,
          ),
        );
      },
      loading: () => const PageSkeletonShell<Object>(
        isLoading: true,
        skeleton: ActivityFeedSkeleton(),
        child: SizedBox.shrink(),
      ),
      error: (_, _) => Center(
        child: AppEmptyState.error(
          title: l10n.commonLoadFailed,
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(activityFeedProvider),
        ),
      ),
    );
  }
}

class _RefreshableFeed extends StatelessWidget {
  const _RefreshableFeed({required this.onRefresh, required this.child});

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(onRefresh: onRefresh, child: child);
  }
}

class _FeedList extends ConsumerStatefulWidget {
  const _FeedList({
    required this.groups,
    required this.pageTotals,
    required this.accountsById,
    required this.formatter,
    required this.l10n,
    required this.hasMore,
  });

  final List<ActivityDaySection> groups;
  final ActivityPageTotals pageTotals;
  final Map<String, Account> accountsById;
  final AppFormatters formatter;
  final AppLocalizations l10n;
  final bool hasMore;

  @override
  ConsumerState<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends ConsumerState<_FeedList> {
  bool _loadingMore = false;

  Future<void> _tryLoadMore() async {
    if (!widget.hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    ref.read(activityFeedQueryProvider.notifier).loadMore();
    // Allow the stream to settle before accepting another page request.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _loadingMore = false);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification && n is! OverscrollNotification) {
      return false;
    }
    final metrics = n.metrics;
    if (metrics.pixels >= metrics.maxScrollExtent - 240) {
      _tryLoadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    // +1 summary, +N days, +1 footer
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.s16).copyWith(
          bottom:
              const EdgeInsets.all(AppSpacing.s16).bottom +
              kTabBarOffset +
              MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: groups.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: _PageSummaryStrip(
                totals: widget.pageTotals,
                formatter: widget.formatter,
                l10n: widget.l10n,
              ),
            );
          }
          if (index == groups.length + 1) {
            return _FeedFooter(
              canLoadMore: widget.hasMore,
              loading: _loadingMore,
              l10n: widget.l10n,
              onLoadMore: _tryLoadMore,
            );
          }
          final section = groups[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DaySectionHeader(
                  section: section,
                  formatter: widget.formatter,
                  l10n: widget.l10n,
                ),
                AppGroupedSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (
                        var row = 0;
                        row < section.entries.length;
                        row++
                      ) ...[
                        ActivityFeedEntryRow(
                          entry: section.entries[row],
                          accountsById: widget.accountsById,
                          formatter: widget.formatter,
                        ),
                        if (row != section.entries.length - 1)
                          const AppGroupedDivider(indent: AppSpacing.s56),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PageSummaryStrip extends StatelessWidget {
  const _PageSummaryStrip({
    required this.totals,
    required this.formatter,
    required this.l10n,
  });

  final ActivityPageTotals totals;
  final AppFormatters formatter;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
    return SoftCard.raised(
      borderless: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(
              label: l10n.activityFeedSummaryExpense,
              value: formatter.currency(totals.expenseTotal, code: totals.unit),
              valueColor: totals.expenseTotal > Decimal.zero
                  ? semantic.danger
                  : colors.mutedForeground,
            ),
          ),
          Container(
            width: AppStroke.hairline,
            height: 28,
            color: colors.border,
          ),
          Expanded(
            child: _SummaryMetric(
              label: l10n.activityFeedSummaryIncome,
              value: formatter.currency(totals.incomeTotal, code: totals.unit),
              valueColor: totals.incomeTotal > Decimal.zero
                  ? semantic.success
                  : colors.mutedForeground,
            ),
          ),
          Container(
            width: AppStroke.hairline,
            height: 28,
            color: colors.border,
          ),
          Expanded(
            child: _SummaryMetric(
              label: l10n.activityFeedSummaryCount,
              value: '${totals.count}',
              valueColor: colors.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s4),
        Text(
          value,
          style: context.strongLabelStyle.copyWith(color: valueColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _DaySectionHeader extends StatelessWidget {
  const _DaySectionHeader({
    required this.section,
    required this.formatter,
    required this.l10n,
  });

  final ActivityDaySection section;
  final AppFormatters formatter;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final title = _dayTitle(section.day, l10n, formatter);
    final trailing = _dayTrailing(section, formatter, l10n);
    return SectionHeader(
      title: title,
      trailing: trailing == null
          ? null
          : Text(trailing, style: context.captionStyle),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s8,
        AppSpacing.s4,
        AppSpacing.s8,
      ),
    );
  }
}

String _dayTitle(DateTime day, AppLocalizations l10n, AppFormatters formatter) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == today) return l10n.activityFeedToday;
  if (day == yesterday) return l10n.activityFeedYesterday;
  return formatter.date(day);
}

String? _dayTrailing(
  ActivityDaySection section,
  AppFormatters formatter,
  AppLocalizations l10n,
) {
  final parts = <String>[];
  if (section.hasExpense) {
    parts.add(
      l10n.activityFeedDayExpense(
        formatter.currency(section.expenseTotal, code: section.unit),
      ),
    );
  }
  if (section.hasIncome) {
    parts.add(
      l10n.activityFeedDayIncome(
        formatter.currency(section.incomeTotal, code: section.unit),
      ),
    );
  }
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter({
    required this.canLoadMore,
    required this.loading,
    required this.l10n,
    required this.onLoadMore,
  });

  final bool canLoadMore;
  final bool loading;
  final AppLocalizations l10n;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
      child: Center(
        child: canLoadMore
            ? (loading
                  ? const SizedBox(
                      width: AppIconSizes.md,
                      height: AppIconSizes.md,
                      child: FCircularProgress(),
                    )
                  : FButton(
                      variant: FButtonVariant.ghost,
                      size: FButtonSizeVariant.sm,
                      mainAxisSize: MainAxisSize.min,
                      onPress: onLoadMore,
                      child: Text(l10n.activityFeedLoadMore),
                    ))
            : Text(l10n.activityFeedAllLoaded, style: context.captionStyle),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({
    required this.message,
    this.actionLabel,
    this.onAction,
    this.filtered = false,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
      children: [
        AppEmptyState(
          icon: filtered ? FLucideIcons.filter : FLucideIcons.workflow,
          title: message,
          action: actionLabel != null && onAction != null
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: FButton(
                    mainAxisSize: MainAxisSize.max,
                    onPress: onAction,
                    child: Text(
                      actionLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}
