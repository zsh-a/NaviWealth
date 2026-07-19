import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_feed_row.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'home_section.dart';

/// Last [kHomeActivityPreviewCount] journal entries, using the shared
/// [ActivityFeedEntryRow] so Home and Activity stay visually aligned.
const int kHomeActivityPreviewCount = 5;

class ActivityTimelinePreview extends ConsumerWidget {
  const ActivityTimelinePreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = context.formatters(ref);
    final feedAsync = ref.watch(activityFeedPreviewProvider);
    return feedAsync.when(
      loading: () =>
          const _ActivityPreviewSection(child: _ActivityPreviewSkeleton()),
      error: (e, _) => _ActivityPreviewSection(
        child: _ActivityPreviewError(
          onRetry: () => ref.invalidate(activityFeedPreviewProvider),
        ),
      ),
      data: (page) {
        if (page.entries.isEmpty) return const SizedBox.shrink();
        final entries = page.entries.take(kHomeActivityPreviewCount).toList();
        return _ActivityPreviewSection(
          child: HomeSurface(
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  ActivityFeedEntryRow(
                    entry: entries[i],
                    accountsById: page.accountsById,
                    formatter: formatter,
                    compact: true,
                  ),
                  if (i < entries.length - 1)
                    const AppGroupedDivider(indent: AppSpacing.s56),
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
    return HomeSection(
      title: l10n.dashboardActivityPreviewTitle,
      actionLabel: l10n.dashboardActivityPreviewViewAll,
      onAction: () => context.go(FinanceRoutes.activity),
      child: child,
    );
  }
}

class _ActivityPreviewSkeleton extends StatelessWidget {
  const _ActivityPreviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return const HomeSurface(
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
    return HomeSurface(
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
