import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';

import '../../../../core/format/formatters.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/activity_feed_provider.dart';
import 'activity_feed_grouping.dart';
import 'activity_feed_row.dart';

/// Timeline feed that groups journal entries by date and renders each
/// as an expandable row.
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
            ),
          );
        }
        final groups = groupActivityEntriesByDate(page.entries);
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
          action: FButton(
            variant: FButtonVariant.ghost,
            onPress: () => ref.invalidate(activityFeedProvider),
            child: Text(l10n.commonRetry),
          ),
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

class _FeedList extends StatelessWidget {
  const _FeedList({
    required this.groups,
    required this.accountsById,
    required this.formatter,
    required this.l10n,
    required this.hasMore,
  });

  final List<ActivityDateSection> groups;
  final Map<String, Account> accountsById;
  final AppFormatters formatter;
  final AppLocalizations l10n;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    final items = <_FeedItem>[];
    for (final section in groups) {
      items.add(_FeedItem.header(section.group));
      for (final entry in section.entries) {
        items.add(_FeedItem.entry(entry));
      }
    }
    items.add(_FeedItem.footer(hasMore));

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.s16).copyWith(
        bottom:
            const EdgeInsets.all(AppSpacing.s16).bottom +
            64 +
            MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return switch (item) {
          _FeedItemHeader(:final group) => _DateSectionHeader(
            group: group,
            l10n: l10n,
          ),
          _FeedItemEntry(:final entry) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: ActivityFeedEntryRow(
              entry: entry,
              accountsById: accountsById,
              formatter: formatter,
            ),
          ),
          _FeedItemFooter(:final canLoadMore) => _FeedFooter(
            canLoadMore: canLoadMore,
            l10n: l10n,
          ),
        };
      },
    );
  }
}

sealed class _FeedItem {
  const _FeedItem();
  factory _FeedItem.header(ActivityDateGroup group) = _FeedItemHeader;
  factory _FeedItem.entry(JournalEntryWithPostings entry) = _FeedItemEntry;
  factory _FeedItem.footer(bool canLoadMore) = _FeedItemFooter;
}

class _FeedItemHeader extends _FeedItem {
  const _FeedItemHeader(this.group);
  final ActivityDateGroup group;
}

class _FeedItemEntry extends _FeedItem {
  const _FeedItemEntry(this.entry);
  final JournalEntryWithPostings entry;
}

class _FeedItemFooter extends _FeedItem {
  const _FeedItemFooter(this.canLoadMore);
  final bool canLoadMore;
}

class _FeedFooter extends ConsumerWidget {
  const _FeedFooter({required this.canLoadMore, required this.l10n});

  final bool canLoadMore;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
      child: Center(
        child: canLoadMore
            ? FButton(
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: ref.read(activityFeedQueryProvider.notifier).loadMore,
                child: Text(l10n.activityFeedLoadMore),
              )
            : Text(l10n.activityFeedAllLoaded, style: context.captionStyle),
      ),
    );
  }
}

class _DateSectionHeader extends StatelessWidget {
  const _DateSectionHeader({required this.group, required this.l10n});

  final ActivityDateGroup group;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final title = switch (group) {
      ActivityDateGroup.today => l10n.activityFeedToday,
      ActivityDateGroup.yesterday => l10n.activityFeedYesterday,
      ActivityDateGroup.thisWeek => l10n.activityFeedThisWeek,
      ActivityDateGroup.earlier => l10n.activityFeedEarlier,
    };
    return SectionHeader(title: title);
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: AppEmptyState(icon: FLucideIcons.workflow, title: message),
        ),
      ],
    );
  }
}
