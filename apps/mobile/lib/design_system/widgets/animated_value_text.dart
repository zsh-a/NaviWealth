import 'package:flutter/widgets.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// Count-up wrapper for non-money headline numbers (scores, counts, steps).
///
/// [AnimatedMoneyText] owns currency formatting; this is the same roll for
/// plain integers / percentages: [format] renders the current interpolated
/// value, so units, grouping, and localization stay in the caller's hands.
///
/// The animation only runs when [value] changes — the first render and any
/// rebuild with an unchanged value show the terminal text, so numbers never
/// replay on unrelated rebuilds. Motion routes through [AppMotionPolicy]
/// (status role): reduced motion snaps straight to the target.
class AnimatedValueText extends StatefulWidget {
  const AnimatedValueText({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.semanticsLabel,
    this.duration = Motion.ticker,
    this.curve = Motion.emphasizedDecelerate,
    this.placeholder = '—',
  });

  /// Current numeric target. Null renders [placeholder] with no animation.
  final num? value;

  /// Renders an interpolated value to text, e.g. `(v) => '${v.round()}%'`.
  final String Function(num value) format;

  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final String? semanticsLabel;

  /// Roll cadence — [Motion.ticker] matches [AnimatedMoneyText].
  final Duration duration;

  /// Easing curve for the tween.
  final Curve curve;

  /// Shown while [value] is null.
  final String placeholder;

  @override
  State<AnimatedValueText> createState() => _AnimatedValueTextState();
}

class _AnimatedValueTextState extends State<AnimatedValueText> {
  num? _previous;

  @override
  void initState() {
    super.initState();
    _previous = widget.value;
  }

  @override
  void didUpdateWidget(covariant AnimatedValueText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previous = oldWidget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.value;

    // Null in or null out → no number to interpolate.
    if (target == null || _previous == null) {
      return _staticText(target);
    }

    if (!AppMotionPolicy.isEnabled(context, role: AppMotionRole.status)) {
      return _staticText(target);
    }

    final from = _previous!.toDouble();
    final to = target.toDouble();
    if (from == to) {
      return _staticText(target);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: from, end: to),
      duration: AppMotionPolicy.duration(
        context,
        widget.duration,
        role: AppMotionRole.status,
      ),
      curve: widget.curve,
      // Once the roll lands, pin _previous to the target so a later rebuild
      // renders statically instead of replaying the same tween.
      onEnd: () => _previous = target,
      builder: (context, value, _) => _staticText(value),
    );
  }

  Widget _staticText(num? value) {
    return Text(
      value == null ? widget.placeholder : widget.format(value),
      style: widget.style,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      semanticsLabel: widget.semanticsLabel,
    );
  }
}
