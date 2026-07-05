part of 'execution_widgets.dart';

class ExecutionStateView extends StatelessWidget {
  const ExecutionStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: icon,
      title: title,
      message: message,
      action: action,
    );
  }
}

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
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppIconSizes.xs, color: colors.mutedForeground),
          const SizedBox(width: AppSpacing.s6),
        ],
        Expanded(
          child: Text(
            title,
            style: context.captionLabelStyle.copyWith(
              color: colors.mutedForeground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AppBadge(
          label: count.toString(),
          size: AppBadgeSize.compact,
          minWidth: AppSpacing.s24,
        ),
      ],
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
      child: FTappable(onPress: onOpen, child: child),
    );
  }
}
