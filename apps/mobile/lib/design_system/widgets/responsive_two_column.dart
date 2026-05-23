import 'package:flutter/material.dart';

import '../tokens/breakpoints.dart';
import '../tokens/dimens_tokens.dart';

/// Switches between a two-column [Row] (wide) and a stacked [Column]
/// (narrow) at [breakpoint].
///
/// Used by content surfaces (FIRE / Analytics / AI Chat) that already sit
/// inside the app shell, so the breakpoint is measured against the
/// surface's own constraints — not the window. The default
/// [Breakpoints.contentTwoColumn] keeps the shell's drawer / rail in mind.
///
/// Each side stretches to fill its share of the available width. Vertical
/// extents are intrinsic — wrap [left] / [right] in a [Column] to compose
/// multiple cards on either side.
class ResponsiveTwoColumn extends StatelessWidget {
  const ResponsiveTwoColumn({
    super.key,
    required this.left,
    required this.right,
    this.breakpoint = Breakpoints.contentTwoColumn,
    this.gap = AppSpacing.s16,
  });

  final Widget left;
  final Widget right;

  /// Minimum available width (in logical pixels) at which the two-column
  /// row engages. Below this the children stack vertically with [gap]
  /// between them.
  final double breakpoint;

  /// Space between the two children in either orientation.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              SizedBox(width: gap),
              Expanded(child: right),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            SizedBox(height: gap),
            right,
          ],
        );
      },
    );
  }
}
