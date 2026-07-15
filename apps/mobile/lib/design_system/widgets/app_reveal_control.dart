import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_interaction.dart';

/// Centered, quiet expand/collapse control for truncated lists.
///
/// Prefer this over a full-width [AppQuietButton] when revealing more of the
/// same list (portfolio positions, secondary metrics, plan actions). Labels
/// are caller-owned so domains can pass localized `More · N` / `Show less`.
class AppRevealControl extends StatelessWidget {
  const AppRevealControl({
    super.key,
    required this.expanded,
    required this.collapsedLabel,
    required this.expandedLabel,
    required this.onToggle,
    this.signalReveal = true,
  });

  final bool expanded;

  /// Label when content is collapsed (e.g. `More · 7`).
  final String collapsedLabel;

  /// Label when content is expanded (e.g. `Show less`).
  final String expandedLabel;

  final VoidCallback onToggle;

  /// When true, fires [AppInteractionIntent.reveal] on press.
  final bool signalReveal;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final label = expanded ? expandedLabel : collapsedLabel;

    return Semantics(
      button: true,
      expanded: expanded,
      label: label,
      child: Center(
        child: FTappable(
          onPress: () {
            if (signalReveal) {
              AppInteraction.signal(AppInteractionIntent.reveal);
            }
            onToggle();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: context.captionLabelStyle.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
                const SizedBox(width: AppSpacing.s4),
                Icon(
                  expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
