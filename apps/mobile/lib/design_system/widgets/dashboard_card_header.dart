import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';

/// A reusable card header with a tinted icon disc, title, and chevron.
///
/// Used on dashboard surfaces (cashflow, passive income, etc.) to give
/// each section a consistent visual identity.
class DashboardCardHeader extends StatelessWidget {
  const DashboardCardHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: AppOpacity.medium),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: AppIconSizes.h18, color: color),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            title,
            style: context.mutedLabelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(
          FLucideIcons.chevronRight,
          size: AppIconSizes.h18,
          color: context.theme.colors.mutedForeground.withValues(
            alpha: AppOpacity.prominent,
          ),
        ),
      ],
    );
  }
}
