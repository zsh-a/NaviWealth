import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Floating pill button that opens the AI chat sheet.
///
/// Rendered as a glass-surfaced capsule with a gradient hairline border
/// (emerald → indigo → violet, 1.5 px) and a sparkle icon. On desktop
/// widths the label "Ask AI" is shown inline; on mobile only the icon
/// is visible.
///
/// The pill is hidden when the user is already on the `/ai` route.
class AiFloatingPill extends StatelessWidget {
  const AiFloatingPill({
    super.key,
    required this.onTap,
    this.onLongPress,
  });

  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const _borderWidth = 1.5;
  static const _gradient = LinearGradient(
    colors: [
      Color(0xFF10B981), // emerald-500
      Color(0xFF6366F1), // indigo-500
      Color(0xFF8B5CF6), // violet-500
    ],
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = Breakpoints.isDesktop(width);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          gradient: _gradient,
          borderRadius: BorderRadius.circular(Radii.full),
        ),
        padding: const EdgeInsets.all(_borderWidth),
        child: GlassSurface(
          sigma: 28,
          borderRadius: BorderRadius.circular(Radii.full),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? Spacing.s16 : Spacing.s12,
              vertical: Spacing.s12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                if (isDesktop) ...[
                  const SizedBox(width: Spacing.s8),
                  Text(
                    AppLocalizations.of(context).aiFloatingPillLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
