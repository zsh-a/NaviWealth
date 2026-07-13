part of 'income_planner_page.dart';

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    return SoftCard.raised(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Text(
          body,
          style: context.bodyCaptionStyle.copyWith(height: 1.45),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard.flat(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.labelStyle.copyWith(color: colors.destructive),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              message,
              style: context.captionStyle.copyWith(
                color: colors.destructive,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
      child: Center(child: FCircularProgress()),
    );
  }
}
