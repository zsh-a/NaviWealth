import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_interaction.dart';
import 'soft_card.dart';

/// Full-width section header for collapsible blocks (Plan tools, Health
/// sources). Pairs with [AnimatedSizeFade] for the body — not for truncating
/// homogeneous list rows (use [AppRevealControl] there).
class AppDisclosureHeader extends StatelessWidget {
  const AppDisclosureHeader({
    super.key,
    required this.title,
    required this.expanded,
    required this.onToggle,
    this.subtitle,
    this.signalReveal = true,
  });

  final String title;
  final String? subtitle;
  final bool expanded;
  final VoidCallback onToggle;
  final bool signalReveal;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard.raised(
      borderless: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      onPress: () {
        if (signalReveal) {
          AppInteraction.signal(AppInteractionIntent.reveal);
        }
        onToggle();
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.rowTitleStyle),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(subtitle!, style: context.captionStyle),
                ],
              ],
            ),
          ),
          Icon(
            expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
            size: AppIconSizes.md,
            color: colors.mutedForeground,
          ),
        ],
      ),
    );
  }
}
