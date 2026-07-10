/// The AI pill primitive.
///
/// Replaces every ad-hoc capsule / chip / outlined-button decoration
/// across AI surfaces. One shape, three states:
///
///   - **neutral** (default): surface tint background, muted label
///   - **selected**: 16% active tone fill + active border + active text
///   - **error**: 12% error fill, error border, error text
///
/// Optionally takes a [leading] widget (a [AiSparkle] or icon) — pill
/// inherits sizing from [AiType.label]. No elevation, no shadow.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import 'ai_motion.dart';
import 'ai_tone.dart';
import 'ai_typography.dart';

enum AiPillState { neutral, selected, error }

class AiPill extends StatelessWidget {
  const AiPill({
    super.key,
    required this.label,
    this.leading,
    this.state = AiPillState.neutral,
    this.onTap,
  });

  final String label;
  final Widget? leading;
  final AiPillState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color tone = switch (state) {
      AiPillState.neutral => AiTone.muted(context),
      AiPillState.selected => AiTone.active(context),
      AiPillState.error => AiTone.error(context),
    };
    final Color bg = switch (state) {
      AiPillState.neutral => AiTone.surfaceTint(
        context,
      ).withValues(alpha: AppOpacity.prominent),
      AiPillState.selected => tone.withValues(alpha: AppOpacity.medium),
      AiPillState.error => tone.withValues(alpha: AppOpacity.light),
    };
    final BorderSide side = switch (state) {
      AiPillState.neutral => BorderSide.none,
      AiPillState.selected => BorderSide(
        color: tone,
        width: AppStroke.hairline,
      ),
      AiPillState.error => BorderSide(color: tone, width: AppStroke.hairline),
    };
    final Color fg = switch (state) {
      AiPillState.neutral => AiTone.onSurface(context),
      AiPillState.selected => tone,
      AiPillState.error => tone,
    };

    final pill = AnimatedContainer(
      duration: AiMotion.duration(context, AiMotion.short),
      curve: AiMotion.standard,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s4,
      ),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(side: side),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.s6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              semanticsLabel: label,
              style: AiType.label(context).copyWith(color: fg),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return FTappable(
      semanticsLabel: label,
      excludeSemantics: false,
      selected: state == AiPillState.selected,
      behavior: HitTestBehavior.opaque,
      onPress: onTap,
      focusedOutlineStyle: const FFocusedOutlineStyleDelta.delta(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.full)),
      ),
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
            ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
            ActivateIntent(),
        // Consume repeats here so they cannot bubble to WidgetsApp's default
        // Enter/Space shortcuts, which accept repeated key events.
        SingleActivator(LogicalKeyboardKey.enter): DoNothingIntent(),
        SingleActivator(LogicalKeyboardKey.space): DoNothingIntent(),
      },
      child: ExcludeSemantics(child: pill),
    );
  }
}
