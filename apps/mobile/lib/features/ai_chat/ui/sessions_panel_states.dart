part of 'sessions_panel.dart';

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({
    required this.icon,
    required this.message,
    this.iconColor,
    this.action,
  });

  final IconData icon;
  final String message;
  final Color? iconColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppIconSizes.xl,
              color: iconColor ?? colors.mutedForeground,
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.bodyCaptionStyle,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.s16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
