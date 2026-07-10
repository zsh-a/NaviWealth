part of 'trend_card.dart';

class _TrendSkeleton extends StatelessWidget {
  const _TrendSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonBox(height: 220, radius: 8);
  }
}

class _TrendError extends StatelessWidget {
  const _TrendError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
      child: Center(
        child: Text(
          userSafeErrorMessage(
            context,
            error,
            operation: 'load dashboard trend',
          ),
          style: context.captionStyle.copyWith(
            color: context.theme.colors.destructive,
          ),
        ),
      ),
    );
  }
}
