part of 'execution_widgets.dart';

class ExecutionSectionHeader extends StatelessWidget {
  const ExecutionSectionHeader({
    super.key,
    required this.title,
    required this.count,
    this.icon,
  });

  final String title;
  final int count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SectionHeader.module(
      title: title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppIconSizes.xs, color: colors.mutedForeground),
            const SizedBox(width: AppSpacing.s6),
          ],
          AppBadge(
            label: count.toString(),
            size: AppBadgeSize.compact,
            minWidth: AppSpacing.s24,
          ),
        ],
      ),
    );
  }
}

class _CardOpenRegion extends StatelessWidget {
  const _CardOpenRegion({required this.child, this.onOpen});

  final Widget child;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    if (onOpen == null) return child;
    return Semantics(
      button: true,
      child: AppTappable(onPress: onOpen, child: child),
    );
  }
}
