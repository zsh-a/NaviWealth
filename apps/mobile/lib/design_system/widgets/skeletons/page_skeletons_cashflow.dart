part of 'page_skeletons.dart';

/// Mirrors `CashFlowPage`: period chips plus KPI cards, then chart and
/// category-mix panels.
class CashFlowSkeleton extends StatelessWidget {
  const CashFlowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    const kpi = SkeletonCard(
      padding: EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 72, height: 12, radius: AppRadius.xs),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(width: 120, height: 24, radius: AppRadius.sm),
        ],
      ),
    );
    const charts = SkeletonCard(
      padding: EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 140, height: 16, radius: AppRadius.xs),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(height: 180, radius: AppRadius.sm),
          SizedBox(height: AppSpacing.s20),
          SkeletonBox(width: 140, height: 16, radius: AppRadius.xs),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(height: 220, radius: AppRadius.sm),
        ],
      ),
    );
    const category = SkeletonCard(
      padding: EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 120, height: 16, radius: AppRadius.xs),
          SizedBox(height: AppSpacing.s12),
          Center(
            child: SkeletonBox(width: 160, height: 160, radius: AppRadius.full),
          ),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(height: 14),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(height: 14),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(height: 14),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        return ListView(
          padding: isWide
              ? const EdgeInsets.all(AppSpacing.s24)
              : const EdgeInsets.all(AppSpacing.s16),
          children: const [
            Row(
              children: [
                SkeletonBox(width: 64, height: 32, radius: AppRadius.full),
                SizedBox(width: AppSpacing.s8),
                SkeletonBox(width: 64, height: 32, radius: AppRadius.full),
                SizedBox(width: AppSpacing.s8),
                SkeletonBox(width: 64, height: 32, radius: AppRadius.full),
              ],
            ),
            SizedBox(height: AppSpacing.s16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: kpi),
                  SizedBox(width: AppSpacing.s12),
                  Expanded(child: kpi),
                  SizedBox(width: AppSpacing.s12),
                  Expanded(child: kpi),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.s16),
            ResponsiveTwoColumn(left: charts, right: category),
          ],
        );
      },
    );
  }
}

/// Mirrors `DividendCenterPage`: KPI grid, holdings ranking, forecast strip,
/// and history timeline.
class DividendCenterSkeleton extends StatelessWidget {
  const DividendCenterSkeleton({super.key});

  static Widget _metric() => const SkeletonCard(
    padding: EdgeInsets.all(AppSpacing.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 64, height: 12, radius: AppRadius.xs),
        SizedBox(height: AppSpacing.s8),
        SkeletonBox(width: 96, height: 22, radius: AppRadius.sm),
      ],
    ),
  );

  static Widget _listCard(int rows) => SkeletonCard(
    padding: const EdgeInsets.all(AppSpacing.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(width: 140, height: 16, radius: AppRadius.xs),
        const SizedBox(height: AppSpacing.s12),
        for (var i = 0; i < rows; i++) ...[
          if (i != 0) const SizedBox(height: AppSpacing.s12),
          const SkeletonBox(height: 16),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        return ListView(
          padding: isWide
              ? const EdgeInsets.all(AppSpacing.s24)
              : const EdgeInsets.all(AppSpacing.s16),
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _metric()),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(child: _metric()),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _metric()),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(child: _metric()),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            _listCard(6),
            const SizedBox(height: AppSpacing.s16),
            const SkeletonCard(
              padding: EdgeInsets.all(AppSpacing.s16),
              child: Row(
                children: [
                  SkeletonBox(width: 24, height: 24, radius: AppRadius.full),
                  SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: SkeletonBox(height: 42, radius: AppRadius.sm),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            _listCard(5),
          ],
        );
      },
    );
  }
}
