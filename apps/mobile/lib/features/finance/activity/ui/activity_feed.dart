import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/shell/shell_chrome.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/activity_feed_provider.dart';
import 'activity_feed_filter_sheet.dart';
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
              actionLabel: page.isFiltered
                  ? l10n.activityFeedFilterTitle
                  : null,
              onAction: page.isFiltered
                  ? () => ActivityFeedFilterSheet.show(context)
                  : null,
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
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.s16).copyWith(
        bottom:
            const EdgeInsets.all(AppSpacing.s16).bottom +
            kTabBarOffset +
            MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: groups.length + 1,
      itemBuilder: (context, index) {
        if (index == groups.length) {
          return _FeedFooter(canLoadMore: hasMore, l10n: l10n);
        }
        final section = groups[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DateSectionHeader(group: section.group, l10n: l10n),
              AppGroupedSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var row = 0; row < section.entries.length; row++) ...[
                      ActivityFeedEntryRow(
                        entry: section.entries[row],
                        accountsById: accountsById,
                        formatter: formatter,
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
    );
  }
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
  const _EmptyFeed({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
      children: [
        AppEmptyState(
          icon: FLucideIcons.workflow,
          title: message,
          action: actionLabel != null && onAction != null
              ? FButton(
                  mainAxisSize: MainAxisSize.min,
                  onPress: onAction,
                  prefix: const Icon(FLucideIcons.filter),
                  child: Text(actionLabel!),
                )
              : null,
        ),
      ],
    );
  }
}
