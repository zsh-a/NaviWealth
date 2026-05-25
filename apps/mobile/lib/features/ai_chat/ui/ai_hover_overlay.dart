/// Hover-/long-press-revealed AI affordance overlay.
///
/// Replaces the "always-on" header pill pattern that used to render
/// `AiObjectCapsule` inline. The card body itself takes back the full
/// chrome row; the capsule lives in a [Stack] overlay anchored just
/// outside the card's top-right corner and is hidden until the user
/// invites it in.
///
/// Visibility rules:
///   - Hover (desktop / web with a mouse): capsule fades in while the
///     pointer is over the card.
///   - Long-press (touch): capsule fades in and sticks for a short
///     window so the user can lift their finger and tap it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/ai/visual/ai_motion.dart';

class AiHoverOverlay extends StatefulWidget {
  const AiHoverOverlay({
    super.key,
    required this.child,
    required this.capsule,
    this.topOffset = -12,
    this.endOffset = 8,
    this.revealHoldDuration = const Duration(seconds: 4),
  });

  /// The card body the overlay is anchored to.
  final Widget child;

  /// The capsule (e.g. `AiObjectCapsule` / `FireAiCapsule`) that should
  /// appear on hover or long-press. May be `SizedBox.shrink()` when the
  /// AI runtime is unavailable — the overlay degrades gracefully.
  final Widget capsule;

  /// Vertical offset (negative pulls the capsule above the card's top
  /// edge — matches the Notion-style "floating outside the corner" look).
  final double topOffset;

  /// Horizontal distance from the card's trailing edge.
  final double endOffset;

  /// How long the capsule stays visible after a long-press reveal on
  /// touch platforms before fading back out.
  final Duration revealHoldDuration;

  @override
  State<AiHoverOverlay> createState() => _AiHoverOverlayState();
}

class _AiHoverOverlayState extends State<AiHoverOverlay> {
  bool _hovering = false;
  bool _touchRevealed = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onLongPress() {
    setState(() => _touchRevealed = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.revealHoldDuration, () {
      if (!mounted) return;
      setState(() => _touchRevealed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _hovering || _touchRevealed;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPress: _onLongPress,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            PositionedDirectional(
              top: widget.topOffset,
              end: widget.endOffset,
              child: IgnorePointer(
                ignoring: !visible,
                child: AnimatedSlide(
                  offset: visible ? Offset.zero : const Offset(0, -0.2),
                  duration: AiMotion.short,
                  curve: AiMotion.standard,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: AiMotion.short,
                    curve: AiMotion.standard,
                    child: widget.capsule,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
