/// Wave 36 — the AI pill primitive.
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

import 'package:flutter/material.dart';

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
      AiPillState.neutral =>
        AiTone.surfaceTint(context).withValues(alpha: 0.6),
      AiPillState.selected => tone.withValues(alpha: 0.16),
      AiPillState.error => tone.withValues(alpha: 0.12),
    };
    final BorderSide side = switch (state) {
      AiPillState.neutral => BorderSide.none,
      AiPillState.selected => BorderSide(color: tone, width: 1),
      AiPillState.error => BorderSide(color: tone, width: 1),
    };
    final Color fg = switch (state) {
      AiPillState.neutral => AiTone.onSurface(context),
      AiPillState.selected => tone,
      AiPillState.error => tone,
    };

    final pill = AnimatedContainer(
      duration: AiMotion.short,
      curve: AiMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(side: side),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AiType.label(context).copyWith(color: fg),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: pill,
      ),
    );
  }
}
