part of 'page_skeletons.dart';

/// Mirrors `HomePage`: hero net-worth card on top, allocation pie and trend
/// chart side-by-side on wide breakpoints, stacked on mobile.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        final padding = isWide
            ? const EdgeInsets.all(AppSpacing.s24)
            : const EdgeInsets.all(AppSpacing.s16);
        const allocation = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 18, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s16),
              Center(
                child: SkeletonBox(
                  width: 200,
                  height: 200,
                  radius: AppRadius.full,
                ),
              ),
              SizedBox(height: AppSpacing.s16),
              SkeletonBox(height: 14),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(height: 14),
            ],
          ),
        );
        const trend = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 18, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 32, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 220, radius: AppRadius.sm),
            ],
          ),
        );
        const header = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 88, height: 14, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 220, height: 36, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 180, height: 12, radius: AppRadius.sm),
            ],
          ),
        );
        if (isWide) {
          return ListView(
            padding: padding,
            children: const [
              header,
              SizedBox(height: AppSpacing.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: allocation),
                  SizedBox(width: AppSpacing.s16),
                  Expanded(child: trend),
                ],
              ),
            ],
          );
        }
        return ListView(
          padding: padding,
          children: const [
            header,
            SizedBox(height: AppSpacing.s12),
            allocation,
            SizedBox(height: AppSpacing.s12),
            trend,
          ],
        );
      },
    );
  }
}

/// Displays allocation content on the left, risk and
/// benchmark content on the right; collapses to one column on mobile.
class AnalyticsSkeleton extends StatelessWidget {
  const AnalyticsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    const left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(width: 160, height: 20, radius: AppRadius.sm),
        SizedBox(height: AppSpacing.s8),
        SkeletonBox(width: 240, height: 14, radius: AppRadius.sm),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: 40, radius: AppRadius.sm),
        SizedBox(height: AppSpacing.s16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SkeletonBox(width: 120, height: 14),
            SkeletonBox(width: 120, height: 18),
          ],
        ),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: 220, radius: AppRadius.sm),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: 56, radius: AppRadius.sm),
        SizedBox(height: AppSpacing.s8),
        SkeletonBox(height: 56, radius: AppRadius.sm),
      ],
    );
    const right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 16, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(height: 14),
              SizedBox(height: AppSpacing.s4),
              SkeletonBox(height: 14),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.s24),
        SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160, height: 16, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 140, radius: AppRadius.sm),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        return ListView(
          padding: isWide
              ? const EdgeInsets.all(AppSpacing.s24)
              : const EdgeInsets.all(AppSpacing.s16),
          children: const [ResponsiveTwoColumn(left: left, right: right)],
        );
      },
    );
  }
}

/// Mirrors `FirePage`: hero progress card with a circular gauge, plus the
/// secondary scenario and sensitivity blocks.
class FireSkeleton extends StatelessWidget {
  const FireSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: const [
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 18),
              SizedBox(height: AppSpacing.s12),
              Center(
                child: SkeletonBox(
                  width: 200,
                  height: 200,
                  radius: AppRadius.full,
                ),
              ),
              SizedBox(height: AppSpacing.s16),
              SkeletonBox(height: 14),
              SizedBox(height: AppSpacing.s4),
              SkeletonBox(height: 14, width: 220),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.s12),
        SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 16),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(width: 200, height: 28, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s4),
              SkeletonBox(width: 160, height: 12),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.s12),
        SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160, height: 16),
              SizedBox(height: AppSpacing.s12),
              SkeletonBox(height: 180, radius: AppRadius.sm),
            ],
          ),
        ),
      ],
    );
  }
}
