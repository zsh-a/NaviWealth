part of '../ai_models_page.dart';

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.color, this.progress});

  final String text;
  final Color color;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8 + AppSpacing.s2,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppOpacity.medium),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: context.theme.typography.body.xs2.copyWith(color: color),
          ),
          if (progress != null) ...[
            const SizedBox(width: AppSpacing.s6),
            Text(
              AppFormatters(locale: Localizations.localeOf(context))
                  .percent(progress!, decimalDigits: 0),
              style: context.theme.typography.body.xs2.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
