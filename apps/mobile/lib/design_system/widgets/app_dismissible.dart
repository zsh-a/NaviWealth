import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_interaction.dart';

/// Tone of the revealed swipe background.
enum AppDismissibleTone { danger, primary }

/// The one swipe-action grammar for list rows (audit §1).
///
/// Replaces four divergent `Dismissible` dialects (different fills, radii,
/// alignments, thresholds and haptics) with a single treatment:
///
/// * end-to-start swipe only, RTL-safe alignment;
/// * background = the tone's container with its onContainer icon/label —
///   never a full-strength fill;
/// * a semantic haptic fires exactly when the action is confirmed;
/// * [confirm] gates the action (e.g. a destructive dialog); when
///   [removeRow] is false the row snaps back and [onTrigger] owns the
///   mutation — the pattern for rows whose deletion re-flows a list the
///   caller animates itself.
class AppDismissible extends StatelessWidget {
  const AppDismissible({
    super.key,
    required this.itemKey,
    required this.child,
    this.tone = AppDismissibleTone.danger,
    this.icon = FLucideIcons.trash2,
    this.label,
    this.borderRadius = AppRadius.md,
    this.confirm,
    this.removeRow = true,
    this.onTrigger,
    this.onDismissed,
  });

  /// Identity of the row inside its list.
  final Key itemKey;

  final Widget child;
  final AppDismissibleTone tone;
  final IconData icon;

  /// Optional short label next to the icon.
  final String? label;

  /// Corner rounding of the revealed background — match the row's shape.
  final double borderRadius;

  /// Gate the action (confirm dialog, async validation). Returning false
  /// snaps the row back with no haptic.
  final Future<bool> Function()? confirm;

  /// When false, the row never leaves the tree: [onTrigger] runs and the
  /// row snaps back (caller-owned list mutation/animation).
  final bool removeRow;

  final VoidCallback? onTrigger;

  /// Called after the row is actually dismissed (only when [removeRow]).
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) {
    final role = switch (tone) {
      AppDismissibleTone.danger => context.appTheme.status.danger,
      AppDismissibleTone.primary => context.appTheme.accent,
    };
    final intent = switch (tone) {
      AppDismissibleTone.danger => AppInteractionIntent.destroy,
      AppDismissibleTone.primary => AppInteractionIntent.commit,
    };
    return Dismissible(
      key: itemKey,
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: AppSpacing.s16),
        decoration: BoxDecoration(
          color: role.container,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.h18, color: role.onContainer),
            if (label != null) ...[
              const SizedBox(width: AppSpacing.s6),
              Text(
                label!,
                style: context.labelStyle.copyWith(color: role.onContainer),
              ),
            ],
          ],
        ),
      ),
      confirmDismiss: (_) async {
        final ok = confirm == null || await confirm!();
        if (!ok) return false;
        AppInteraction.signal(intent);
        if (!removeRow) {
          onTrigger?.call();
          return false;
        }
        onTrigger?.call();
        return true;
      },
      onDismissed: onDismissed == null ? null : (_) => onDismissed!(),
      child: child,
    );
  }
}
