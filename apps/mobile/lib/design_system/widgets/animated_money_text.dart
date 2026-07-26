import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'money_text.dart';

/// CountUp-style wrapper around [MoneyText] that smoothly animates between
/// the previous and next [amount] when the value changes.
///
/// All non-amount props mirror [MoneyText] one-to-one — drop-in replacement
/// at any hero / KPI / list-row site that wants its number to roll instead
/// of snap. The animation respects [MediaQueryData.disableAnimations] and
/// degrades to the terminal value, and a shorter cadence is used for small
/// same-sign deltas so a tiny tick doesn't take the full marquee duration.
///
/// Currency / sign / locale / fraction-digit semantics live in [MoneyText].
/// The only added behaviour here is the interpolation.
class AnimatedMoneyText extends StatefulWidget {
  const AnimatedMoneyText({
    super.key,
    required this.amount,
    this.currencyCode = 'CNY',
    this.symbol,
    this.symbolStyle = MoneySymbolStyle.symbol,
    this.fractionDigits,
    this.style,
    this.color,
    this.locale,
    this.textAlign,
    this.compact = false,
    this.showSign = false,
    this.semanticsLabel,
    this.duration = Motion.ticker,
    this.shortDuration = Motion.ambient,
    this.curve = Motion.emphasizedDecelerate,
    this.shortDeltaThreshold = 0.05,
    this.minDeltaThreshold = 0,
    this.highlightChanges = true,
  });

  // -- MoneyText pass-through props -----------------------------------------

  final num? amount;
  final String currencyCode;
  final String? symbol;
  final MoneySymbolStyle symbolStyle;
  final int? fractionDigits;
  final TextStyle? style;
  final Color? color;
  final String? locale;
  final TextAlign? textAlign;
  final bool compact;
  final bool showSign;
  final String? semanticsLabel;

  // -- Animation knobs ------------------------------------------------------

  /// Default cadence — 800ms feels marquee-like at hero sizes.
  final Duration duration;

  /// Shorter cadence used when the change is small and same-sign — keeps
  /// minor ticks (a 0.3% list-row update) from blocking the eye for the
  /// full hero duration.
  final Duration shortDuration;

  /// Easing curve for the tween.
  final Curve curve;

  /// Relative-change threshold under which [shortDuration] is used (in
  /// addition to a same-sign requirement). 0.05 = 5%.
  final double shortDeltaThreshold;

  /// Relative-change threshold below which the widget does NOT animate at
  /// all (snaps directly to the new value). Useful in dense list rows where
  /// many sub-1% ticks would otherwise make the whole table shimmy. 0 (the
  /// default) means every change animates.
  final double minDeltaThreshold;

  /// Pulse a direction-colored wash (12% alpha, fade in/out) behind the
  /// number while it rolls, so a live update reads as "this just moved up /
  /// down" without the reader re-parsing digits. Color routes through
  /// `theme.market`, so the up/down preference and colorblind mode apply.
  final bool highlightChanges;

  @override
  State<AnimatedMoneyText> createState() => _AnimatedMoneyTextState();
}

class _AnimatedMoneyTextState extends State<AnimatedMoneyText> {
  num? _previous;
  int _pulseSeq = 0;
  int _pulseDirection = 0;

  @override
  void initState() {
    super.initState();
    _previous = widget.amount;
  }

  @override
  void didUpdateWidget(covariant AnimatedMoneyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amount != widget.amount) {
      _previous = oldWidget.amount;
      final from = oldWidget.amount;
      final to = widget.amount;
      if (from != null && to != null && from != to) {
        _pulseDirection = to > from ? 1 : -1;
        _pulseSeq++;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final motionEnabled = AppMotionPolicy.isEnabled(
      context,
      role: AppMotionRole.status,
    );
    final target = widget.amount;

    // Null in or null out → no number to interpolate. Defer to MoneyText's
    // placeholder ("¥ —") and skip the animation.
    if (target == null || _previous == null) {
      return _staticMoneyText(target);
    }

    if (!motionEnabled) {
      return _staticMoneyText(target);
    }

    final from = _previous!.toDouble();
    final to = target.toDouble();

    if (_isUnderMinThreshold(from, to)) {
      return _staticMoneyText(target);
    }

    final duration = _pickDuration(from, to);

    return _withChangePulse(
      TweenAnimationBuilder<double>(
        key: ValueKey<String>(
          '${widget.currencyCode}|${widget.compact}|${widget.symbolStyle.index}',
        ),
        tween: Tween<double>(begin: from, end: to),
        duration: AppMotionPolicy.duration(
          context,
          duration,
          role: AppMotionRole.status,
        ),
        curve: widget.curve,
        builder: (context, value, _) => _staticMoneyText(value),
      ),
    );
  }

  /// One sine-shaped wash (0 → 12% alpha → 0 over [Motion.ticker]) behind
  /// the rolling number, restarted per change via [_pulseSeq].
  Widget _withChangePulse(Widget child) {
    if (!widget.highlightChanges || _pulseSeq == 0 || _pulseDirection == 0) {
      return child;
    }
    final tint = context.appTheme.market.roleForDelta(_pulseDirection).fg;
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(_pulseSeq),
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotionPolicy.duration(
        context,
        Motion.ticker,
        role: AppMotionRole.status,
      ),
      curve: Curves.linear,
      builder: (context, t, inner) => DecoratedBox(
        decoration: BoxDecoration(
          color: tint.withValues(
            alpha: math.sin(math.pi * t) * AppOpacity.light,
          ),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: inner,
      ),
      child: child,
    );
  }

  bool _isUnderMinThreshold(double from, double to) {
    if (widget.minDeltaThreshold <= 0) return false;
    if (from == to) return true;
    final magnitude = from.abs() < to.abs() ? to.abs() : from.abs();
    if (magnitude == 0) return false;
    final relative = (to - from).abs() / magnitude;
    return relative < widget.minDeltaThreshold;
  }

  Duration _pickDuration(double from, double to) {
    if (from == to) return Duration.zero;
    // Same-sign + small relative change → use the shorter cadence so list
    // rows don't sit in 800ms transitions for a 0.3% tick.
    final sameSign = (from >= 0) == (to >= 0);
    if (sameSign) {
      final magnitude = from.abs() < to.abs() ? to.abs() : from.abs();
      if (magnitude > 0) {
        final relative = (to - from).abs() / magnitude;
        if (relative < widget.shortDeltaThreshold) return widget.shortDuration;
      }
    }
    return widget.duration;
  }

  Widget _staticMoneyText(num? value) {
    return MoneyText(
      amount: value,
      currencyCode: widget.currencyCode,
      symbol: widget.symbol,
      symbolStyle: widget.symbolStyle,
      fractionDigits: widget.fractionDigits,
      style: widget.style,
      color: widget.color,
      locale: widget.locale,
      textAlign: widget.textAlign,
      compact: widget.compact,
      showSign: widget.showSign,
      semanticsLabel: widget.semanticsLabel,
    );
  }
}
