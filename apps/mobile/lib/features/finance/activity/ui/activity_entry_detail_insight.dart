part of 'activity_entry_detail_page.dart';

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({required this.insight});

  final String insight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              FLucideIcons.sparkles,
              size: AppIconSizes.xs,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.activityEntryDetailAiExplanation,
                  style: context.labelStyle,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  insight,
                  style: context.bodyCaptionStyle.copyWith(height: 1.38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
