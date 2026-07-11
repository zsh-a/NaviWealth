import 'package:flutter/material.dart';

import '../tokens/app_motion_policy.dart';

/// `Hero` wrapper that becomes a no-op when [enabled] is false.
///
/// List → detail Hero animations only make sense when navigation actually
/// pushes a new route. In the desktop master-detail layout the list and the
/// detail are mounted side-by-side inside the same `Navigator`, so two
/// `Hero` widgets would share a tag on the same screen — Flutter asserts.
/// Pass `enabled: false` from list tiles when they render inside a
/// master-detail surface.
///
/// The default [flightShuttleBuilder] re-parents the in-flight widget under
/// a `Material` of type [MaterialType.transparency] so text/icons keep their
/// colour and `MoneyText`'s `Text.rich` doesn't lose its inherited
/// `DefaultTextStyle` mid-flight.
class OptionalHero extends StatelessWidget {
  const OptionalHero({
    super.key,
    required this.tag,
    required this.child,
    this.enabled = true,
    this.flightShuttleBuilder,
    this.placeholderBuilder,
    this.transitionOnUserGestures = false,
  });

  final Object tag;
  final Widget child;
  final bool enabled;
  final HeroFlightShuttleBuilder? flightShuttleBuilder;
  final HeroPlaceholderBuilder? placeholderBuilder;
  final bool transitionOnUserGestures;

  @override
  Widget build(BuildContext context) {
    if (!enabled ||
        !AppMotionPolicy.isEnabled(context, role: AppMotionRole.transition)) {
      return child;
    }
    return Hero(
      tag: tag,
      flightShuttleBuilder: flightShuttleBuilder ?? _defaultShuttle,
      placeholderBuilder: placeholderBuilder,
      transitionOnUserGestures: transitionOnUserGestures,
      child: child,
    );
  }

  static Widget _defaultShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final toHero = toHeroContext.widget as Hero;
    return Material(type: MaterialType.transparency, child: toHero.child);
  }
}
