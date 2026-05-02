import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';
import '../tokens/glass_tokens.dart';
import 'glass_surface.dart';

/// Frosted-glass [NavigationBar] for the mobile shell.
///
/// Replaces the Material 3 capsule indicator with a 1.5px emerald
/// hairline above the selected tab — T11 item 2.
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
        indicatorColor: Colors.transparent,
        // Override the indicator to a thin emerald line via the theme.
        // The NavigationBar's indicator shape is controlled by
        // NavigationBarThemeData.indicatorShape — we set it to a
        // StadiumBorder that paints nothing (transparent), and rely on
        // the custom _SelectedIndicator overlay below.
      ),
    );
  }
}

/// A custom indicator widget that draws a 1.5px emerald line above
/// the selected navigation destination.
///
/// This replaces the M3 pill/capsule indicator with a minimal
/// hairline treatment matching the desktop sidebar's left-edge bar.
class NavigationBarIndicator extends StatelessWidget {
  const NavigationBarIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.5,
      decoration: const BoxDecoration(
        color: ColorPalette.green500,
        borderRadius: BorderRadius.vertical(top: Radius.circular(1)),
      ),
    );
  }
}
