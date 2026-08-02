import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_tappable.dart';

/// Quiet operational metadata for healthy or expected states.
///
/// Use [AppStatusBanner] for failures and work that needs attention. Freshness,
/// provenance, and successful background activity belong here so normal state
/// does not compete with the page's primary content.
class AppStatusLine extends StatelessWidget {
  const AppStatusLine({
    super.key,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onPress,
    this.semanticLabel,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onPress;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: onPress == null ? 0 : AppControlHeights.touchTarget,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s4,
        ),
        child: Row(
          children: [
            Icon(icon, size: AppIconSizes.h18, color: colors.mutedForeground),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                message,
                style: context.captionStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: AppSpacing.s8),
              Text(
                actionLabel!,
                style: context.captionLabelStyle.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (onPress == null) return content;
    return Semantics(
      button: true,
      label: semanticLabel ?? message,
      child: AppTappable(
        onPress: onPress,
        excludeSemantics: true,
        child: content,
      ),
    );
  }
}
