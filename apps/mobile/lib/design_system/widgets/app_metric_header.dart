import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';

class AppMetricHeader extends StatelessWidget {
  const AppMetricHeader({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      children: [
        Icon(
          icon,
          size: AppIconSizes.md,
          color: colors.mutedForeground.withValues(alpha: AppOpacity.prominent),
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
          color: colors.mutedForeground.withValues(alpha: AppOpacity.disabled),
        ),
      ],
    );
  }
}
