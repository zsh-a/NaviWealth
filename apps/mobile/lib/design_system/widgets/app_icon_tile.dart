import 'package:flutter/widgets.dart';

import '../tokens/dimens_tokens.dart';

/// Compact tinted icon tile for card headers, rows, and metric chips.
///
/// Keeps HealthOS/KnowledgeOS style accents quiet and consistent: the colour
/// identifies the metric or state, while the tile shape controls visual weight.
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 28,
    this.iconSize = AppIconSizes.sm,
    this.radius = AppRadius.sm,
    this.backgroundOpacity = AppOpacity.subtle,
    this.foregroundOpacity = AppOpacity.prominent,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final double radius;
  final double backgroundOpacity;
  final double foregroundOpacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: backgroundOpacity),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: iconSize,
        color: color.withValues(alpha: foregroundOpacity),
      ),
    );
  }
}
