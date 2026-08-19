part of 'page_skeletons.dart';

/// Mirrors `WealthHubPage`: net-worth hero, trend, destinations, and allocation.
class WealthHubSkeleton extends StatelessWidget {
  const WealthHubSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        final padding = isWide
            ? const EdgeInsets.all(AppSpacing.s24)
            : const EdgeInsets.all(AppSpacing.s16);

        const hero = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 96, height: 14, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 220, height: 36, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s16),
              Row(
                children: [
                  Expanded(
                    child: SkeletonBox(height: 42, radius: AppRadius.sm),
                  ),
                  SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: SkeletonBox(height: 42, radius: AppRadius.sm),
                  ),
                ],
              ),
            ],
          ),
        );

        const trend = SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 128, height: 16, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 44, radius: AppRadius.full),
              SizedBox(height: AppSpacing.s16),
              Row(
                children: [
                  Expanded(child: SkeletonBox(height: AppSpacing.s48)),
                  SizedBox(width: AppSpacing.s16),
                  Expanded(child: SkeletonBox(height: AppSpacing.s48)),
                ],
              ),
              SizedBox(height: AppSpacing.s16),
              SkeletonBox(height: AppChartHeights.standard),
              SizedBox(height: AppSpacing.s16),
              SkeletonBox(height: 44, radius: AppRadius.full),
            ],
          ),
        );

        final destinations = SkeletonCard(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i != 0) const FDivider(),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
                  child: Row(
                    children: [
                      SkeletonBox(
                        width: 36,
                        height: 36,
                        radius: AppRadius.full,
                      ),
                      SizedBox(width: AppSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 140, height: 14),
                            SizedBox(height: AppSpacing.s6),
                            SkeletonBox(width: 88, height: 12),
                          ],
                        ),
                      ),
                      SizedBox(width: AppSpacing.s12),
                      SkeletonBox(width: 80, height: 16),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );

        const allocation = SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 128, height: 16, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s16),
              SkeletonBox(height: AppSpacing.s10, radius: AppRadius.full),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 18),
              SizedBox(height: AppSpacing.s10),
              SkeletonBox(height: 18),
            ],
          ),
        );

        if (isWide) {
          return ListView(
            padding: padding,
            children: [
              hero,
              const SizedBox(height: AppSpacing.s16),
              trend,
              const SizedBox(height: AppSpacing.s16),
              destinations,
              const SizedBox(height: AppSpacing.s16),
              allocation,
            ],
          );
        }

        return ListView(
          padding: padding,
          children: [
            hero,
            const SizedBox(height: AppSpacing.s12),
            trend,
            const SizedBox(height: AppSpacing.s12),
            destinations,
            const SizedBox(height: AppSpacing.s12),
            allocation,
          ],
        );
      },
    );
  }
}

/// Mirrors `ActivityFeed`: filter chips above grouped timeline rows.
class ActivityFeedSkeleton extends StatelessWidget {
  const ActivityFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        const Row(
          children: [
            SkeletonBox(width: 64, height: 32, radius: AppRadius.full),
            SizedBox(width: AppSpacing.s8),
            SkeletonBox(width: 76, height: 32, radius: AppRadius.full),
            SizedBox(width: AppSpacing.s8),
            SkeletonBox(width: 76, height: 32, radius: AppRadius.full),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        for (var i = 0; i < 5; i++) ...[
          if (i != 0) const SizedBox(height: AppSpacing.s12),
          const SkeletonCard(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: Row(
              children: [
                SkeletonBox(width: 40, height: 40, radius: AppRadius.full),
                SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 160, height: 14),
                      SizedBox(height: AppSpacing.s6),
                      SkeletonBox(width: 112, height: 12),
                    ],
                  ),
                ),
                SizedBox(width: AppSpacing.s12),
                SkeletonBox(width: 88, height: 16),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Mirrors a compact wealth-object list: section header plus repeated
/// manual and physical
/// asset rows.
class AssetsListSkeleton extends StatelessWidget {
  const AssetsListSkeleton({super.key, this.rowCount = 3});

  final int rowCount;

  Widget _row() {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        children: [
          SkeletonBox(width: 36, height: 36, radius: AppRadius.full),
          SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 14),
                SizedBox(height: AppSpacing.s6),
                SkeletonBox(width: 88, height: 12),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.s12),
          SkeletonBox(width: 80, height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
          child: SkeletonBox(width: 100, height: 18),
        ),
        FCard(
          child: Column(
            children: [
              for (var i = 0; i < rowCount; i++) ...[
                _row(),
                if (i != rowCount - 1) const FDivider(),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
          child: SkeletonBox(width: 120, height: 18),
        ),
        FCard(child: Column(children: [_row(), const FDivider(), _row()])),
      ],
    );
  }
}

/// Mirrors the asset detail layout: hero summary card, holding / valuation
/// block, and a 30-day chart placeholder.
class AssetDetailSkeleton extends StatelessWidget {
  const AssetDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: const [
        SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 88, height: 14, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 220, height: 32, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 160, height: 12, radius: AppRadius.sm),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.s12),
        SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 80, height: 14, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 18),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(height: 18),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.s12),
        SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 16, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 180, radius: AppRadius.sm),
            ],
          ),
        ),
      ],
    );
  }
}
