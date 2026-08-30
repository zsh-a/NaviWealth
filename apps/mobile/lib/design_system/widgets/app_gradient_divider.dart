import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';

/// Gradient fade divider — opaque→transparent→opaque horizontally for an
/// organic ribbon-grouped feel instead of a hard line.
///
/// Used in settings sections and sheet footers. The [horizontalPadding]
/// controls the inset from the edges; the [stops] control how quickly
/// the fade happens at each end. Pass [color] to override the default
/// whisper-alpha foreground color (e.g. for more prominent separators).
class AppGradientDivider extends StatelessWidget {
  const AppGradientDivider({
    super.key,
    this.horizontalPadding = AppSpacing.s14,
    this.stops = const [0.0, 0.12, 0.88, 1.0],
    this.color,
  });

  final double horizontalPadding;
  final List<double> stops;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        FTheme.of(context).colors.foreground
            .withValues(alpha: AppOpacity.whisper);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          colors: [
            resolved.withValues(alpha: AppOpacity.transparent),
            resolved,
            resolved,
            resolved.withValues(alpha: AppOpacity.transparent),
          ],
          stops: stops,
        ).createShader(rect),
        blendMode: BlendMode.srcIn,
        child: Container(height: 1, color: resolved),
      ),
    );
  }
}
