import 'package:flutter/widgets.dart';

import '../tokens/breakpoints.dart';
import '../tokens/dimens_tokens.dart';

/// A content-local primary/supporting composition.
///
/// Unlike shell navigation, this widget intentionally reads its own
/// constraints. The supporting content stacks below the primary flow on
/// compact surfaces and becomes a stable right pane when enough usable width
/// remains after shell chrome, split-screen, or browser resizing.
class AdaptiveSupportingPane extends StatelessWidget {
  const AdaptiveSupportingPane({
    super.key,
    required this.primary,
    required this.supporting,
    this.breakpoint = Breakpoints.contentTwoColumn,
    this.supportingWidth = kAdaptiveSupportingPaneWidth,
    this.gap = AppSpacing.s24,
    this.stackedGap = AppSpacing.s20,
    this.primaryFlex = 1,
  });

  final Widget primary;
  final Widget supporting;
  final double breakpoint;
  final double supportingWidth;
  final double gap;
  final double stackedGap;
  final int primaryFlex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < breakpoint || textScale > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              SizedBox(height: stackedGap),
              supporting,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: primaryFlex, child: primary),
            SizedBox(width: gap),
            SizedBox(width: supportingWidth, child: supporting),
          ],
        );
      },
    );
  }
}

const double kAdaptiveSupportingPaneWidth = 340;
