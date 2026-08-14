import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/shell/shell_chrome.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data/repositories/journal_entry_providers.dart';
import '../data/activity_feed_provider.dart';
import 'activity_action_panel.dart';
import 'activity_feed_filter_sheet.dart';
import 'activity_feed_grouping.dart';
import 'activity_feed_row.dart';

/// Timeline feed grouped by calendar day with day totals and infinite scroll.
class ActivityFeed extends ConsumerWidget {
  const ActivityFeed({super.key, this.onEntryOpen});

  final ValueChanged<String>? onEntryOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final feedAsync = ref.watch(activityFeedProvider);

    // The scope sits above the loading/data branches so the entrance
    // watermark survives pull-to-refresh: the initial load animates, a
    // refresh re-showing the same rows does not replay.
    return AppEntranceScope(
      child: feedAsync.when(
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
              onEntryOpen: onEntryOpen,
            ),
          );
        },
        loading: () => const PageSkeletonShell<Object>(
          isLoading: true,
          skeleton: ActivityFeedSkeleton(),
          child: SizedBox.shrink(),
        ),
        error: (e, st) => kDefaultError(
          context,
          e,
          st,
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
    return AppRefreshIndicator(onRefresh: onRefresh, child: child);
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
    required this.onEntryOpen,
  });

  final List<ActivityDaySection> groups;
  final ActivityPageTotals pageTotals;
  final Map<String, Account> accountsById;
  final AppFormatters formatter;
  final AppLocalizations l10n;
  final bool hasMore;
  final ValueChanged<String>? onEntryOpen;

  @override
  ConsumerState<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends ConsumerState<_FeedList> {
  bool _loadingMore = false;
  bool _loadMoreFailed = false;

  List<_FeedItem>? _cachedItems;

  @override
  void didUpdateWidget(covariant _FeedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groups != widget.groups) {
      _cachedItems = null;
    }
  }

  List<_FeedItem> _buildItems() {
    _cachedItems ??= _flattenFeedItems(widget.groups);
    return _cachedItems!;
  }

  Future<void> _tryLoadMore() async {
    if (!widget.hasMore || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    ref.read(activityFeedQueryProvider.notifier).loadMore();
    try {
      await ref.read(activityFeedProvider.future);
    } catch (_) {
      if (mounted) setState(() => _loadMoreFailed = true);
    }
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
    final items = _buildItems();
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellTabContentPadding(context),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final row = switch (item) {
            _FeedSummaryItem() => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: _PageSummaryStrip(
                totals: widget.pageTotals,
                formatter: widget.formatter,
                l10n: widget.l10n,
                hasMore: widget.hasMore,
              ),
            ),
            _FeedDayHeaderItem(:final section) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: _DaySectionHeader(
                section: section,
                formatter: widget.formatter,
                l10n: widget.l10n,
              ),
            ),
            _FeedEntryItem(
              :final entry,
              :final isFirstInDay,
              :final isLastInDay,
            ) =>
              _VirtualizedDayEntry(
                entry: entry,
                isFirstInDay: isFirstInDay,
                isLastInDay: isLastInDay,
                accountsById: widget.accountsById,
                formatter: widget.formatter,
                onEntryOpen: widget.onEntryOpen,
              ),
            _FeedFooterItem() => _FeedFooter(
              canLoadMore: widget.hasMore,
              loading: _loadingMore,
              failed: _loadMoreFailed,
              l10n: widget.l10n,
              onLoadMore: _tryLoadMore,
            ),
          };
          return AppOnceEntrance(index: index, child: row);
        },
      ),
    );
  }
}

/// Flatten day groups so every journal row is a top-level list item.
/// Nested Columns under each day forced full-day rebuilds and lost
/// virtualization for dense trading days.
List<_FeedItem> _flattenFeedItems(List<ActivityDaySection> groups) {
  final items = <_FeedItem>[const _FeedSummaryItem()];
  for (final section in groups) {
    items.add(_FeedDayHeaderItem(section));
    final entries = section.entries;
    for (var i = 0; i < entries.length; i++) {
      items.add(
        _FeedEntryItem(
          entry: entries[i],
          isFirstInDay: i == 0,
          isLastInDay: i == entries.length - 1,
        ),
      );
    }
  }
  items.add(const _FeedFooterItem());
  return items;
}

sealed class _FeedItem {
  const _FeedItem();
}

class _FeedSummaryItem extends _FeedItem {
  const _FeedSummaryItem();
}

class _FeedDayHeaderItem extends _FeedItem {
  const _FeedDayHeaderItem(this.section);
  final ActivityDaySection section;
}

class _FeedEntryItem extends _FeedItem {
  const _FeedEntryItem({
    required this.entry,
    required this.isFirstInDay,
    required this.isLastInDay,
  });

  final JournalEntryWithPostings entry;
  final bool isFirstInDay;
  final bool isLastInDay;
}

class _FeedFooterItem extends _FeedItem {
  const _FeedFooterItem();
}

/// One entry row with grouped-surface chrome that stitches adjacent rows
/// of the same day into a continuous card without building the whole day.
class _VirtualizedDayEntry extends ConsumerWidget {
  const _VirtualizedDayEntry({
    required this.entry,
    required this.isFirstInDay,
    required this.isLastInDay,
    required this.accountsById,
    required this.formatter,
    required this.onEntryOpen,
  });

  final JournalEntryWithPostings entry;
  final bool isFirstInDay;
  final bool isLastInDay;
  final Map<String, Account> accountsById;
  final AppFormatters formatter;
  final ValueChanged<String>? onEntryOpen;

  /// Swipe-to-delete on the highest-traffic list (audit §1): same confirm
  /// dialog + soft-delete + undo toast as the detail page.
  Future<bool> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.activityEntryDeleteTitle),
      body: Text(l10n.activityEntryDeleteBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return false;
    AppMessenger.cacheOverlay(context);
    try {
      final repo = await ref.read(journalEntryRepositoryProvider.future);
      await repo.softDelete(entry.entry.id);
      ref.invalidate(activityFeedProvider);
      if (context.mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.activityEntryDeleted,
          duration: const Duration(seconds: 6),
          actionLabel: l10n.commonUndo,
          onAction: () => unawaited(_restore(context, ref, repo, l10n)),
        );
      }
      return true;
    } catch (_) {
      if (context.mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.activityEntryDeleteFailed,
        );
      }
      return false;
    }
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    JournalEntryRepository repo,
    AppLocalizations l10n,
  ) async {
    try {
      await repo.restoreSoftDeleted(entry.entry.id);
      ref.invalidate(activityFeedProvider);
    } catch (_) {
      if (context.mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.activityEntryDeleteFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: isLastInDay ? AppSpacing.s12 : AppSpacing.s0,
      ),
      child: AppDismissible(
        itemKey: ValueKey('activity-entry-${entry.entry.id}'),
        borderRadius: AppRadius.lg,
        label: AppLocalizations.of(context).commonDelete,
        confirm: () => _confirmAndDelete(context, ref),
        // The feed re-flows via provider invalidation; no row animation.
        removeRow: false,
        child: ActivityFeedEntrySurface(
          entry: entry,
          accountsById: accountsById,
          formatter: formatter,
          onPress: onEntryOpen == null
              ? null
              : () => onEntryOpen!(entry.entry.id),
          isFirstInGroup: isFirstInDay,
          isLastInGroup: isLastInDay,
        ),
      ),
    );
  }
}

class _PageSummaryStrip extends StatelessWidget {
  const _PageSummaryStrip({
    required this.totals,
    required this.formatter,
    required this.l10n,
    required this.hasMore,
  });

  final ActivityPageTotals totals;
  final AppFormatters formatter;
  final AppLocalizations l10n;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    final status = context.appTheme.status;
    final net = totals.incomeTotal - totals.expenseTotal;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s10,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.theme.colors.border.withValues(
              alpha: AppOpacity.highlight,
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.activityFeedSummaryNet,
                  style: context.captionMediumStyle,
                ),
              ),
              Text(
                hasMore
                    ? l10n.activityFeedSummaryShown(totals.count)
                    : l10n.activityFeedSummaryCountValue(totals.count),
                style: context.captionStyle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          SignedMoneyText(
            amount: net,
            unit: totals.unit,
            formatters: formatter,
            style: context.strongHeadlineStyle,
          ),
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: l10n.activityFeedSummaryIncome,
                  amount: totals.incomeTotal,
                  unit: totals.unit,
                  formatter: formatter,
                  valueColor: totals.incomeTotal > Decimal.zero
                      ? status.success.fg
                      : context.theme.colors.mutedForeground,
                ),
              ),
              const SizedBox(width: AppSpacing.s16),
              Expanded(
                child: _SummaryMetric(
                  label: l10n.activityFeedSummaryExpense,
                  amount: totals.expenseTotal,
                  unit: totals.unit,
                  formatter: formatter,
                  valueColor: context.theme.colors.foreground,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.amount,
    required this.unit,
    required this.formatter,
    required this.valueColor,
  });

  final String label;
  final Decimal amount;
  final String unit;
  final AppFormatters formatter;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: context.captionStyle),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: SignedMoneyText(
            amount: amount,
            unit: unit,
            formatters: formatter,
            showPositiveSign: false,
            colorBySign: false,
            color: valueColor,
            style: context.strongLabelStyle,
            textAlign: TextAlign.end,
          ),
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
    required this.failed,
    required this.l10n,
    required this.onLoadMore,
  });

  final bool canLoadMore;
  final bool loading;
  final bool failed;
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
                  : failed
                  ? FButton(
                      variant: FButtonVariant.ghost,
                      size: FButtonSizeVariant.sm,
                      mainAxisSize: MainAxisSize.min,
                      onPress: onLoadMore,
                      child: Text(l10n.commonRetry),
                    )
                  : const SizedBox(height: AppControlHeights.touchTarget))
            : Container(
                width: AppSpacing.s32,
                height: AppStroke.hairline,
                color: context.theme.colors.border,
              ),
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
