import 'package:flutter/material.dart';

import '../tokens/glass_tokens.dart';
import 'glass_surface.dart';

/// Frosted-glass [NavigationBar] for the mobile shell.
///
/// Wraps the Material [NavigationBar] in a [GlassSurface] with sigma 24 so
/// the canvas underneath bleeds through. We disable the navigation bar's
/// own surface tint and elevation — the glass treatment is the elevation,
/// and any default Material 3 tint on top of our blurred backdrop
/// produces a "muddy" composite (two surfaces composing, neither fully
/// transparent).
///
/// A 1-px hairline at the top edge keeps the bar legible against any
/// content scrolled directly beneath it.
class GlassNavigationBar extends StatelessWidget {
  const GlassNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final List<NavigationDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  static const double _sigma = 24;

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context);
    return GlassSurface(
      sigma: _sigma,
      border: Border(
        top: BorderSide(color: tokens.hairlineColor, width: 1),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        destinations: destinations,
        onDestinationSelected: onDestinationSelected,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
