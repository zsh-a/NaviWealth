import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Standard row for app bottom-sheet action lists.
class AppActionSheetTile extends StatelessWidget {
  const AppActionSheetTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTile(
      onPress: onPress,
      prefix: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colors.foreground.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: colors.mutedForeground),
      ),
      title: Text(
        title,
        style: context.theme.typography.sm.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: context.theme.typography.xs.copyWith(
          color: colors.mutedForeground,
        ),
      ),
    );
  }
}
