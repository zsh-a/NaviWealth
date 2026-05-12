/// Wave 36 — the sparkle primitive.
///
/// **One way** to draw the AI signal across all surfaces:
///   - Outlined glyph (`auto_awesome_outlined`), never filled
///   - Default size 12 (capsule prefix, source mark, banner head)
///   - Default tone [AiTone.muted] (lives quietly until user looks)
///   - Active state uses [AiTone.active] (streaming / live signal)
///
/// Banned: glow, gradients, fill, larger sizes that draw the eye.
/// If your surface needs a louder AI indicator, the answer is
/// **typography**, not a bigger sparkle.
library;

import 'package:flutter/material.dart';

import 'ai_tone.dart';

class AiSparkle extends StatelessWidget {
  const AiSparkle({super.key, this.size = 12, this.active = false});

  final double size;

  /// When `true`, paint with [AiTone.active] instead of [AiTone.muted].
  /// Used for "AI is generating" hints and selected affordances.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.auto_awesome_outlined,
      size: size,
      color: active ? AiTone.active(context) : AiTone.muted(context),
    );
  }
}
