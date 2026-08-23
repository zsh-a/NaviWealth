import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';
import 'app_page_route.dart';

/// Builds the closed state of an [AppContainerTransform]; [open] performs
/// the container-transform push. Matches `OpenContainer.closedBuilder`'s
/// signature so it can be forwarded verbatim.
typedef AppContainerTransformClosedBuilder =
    Widget Function(BuildContext context, VoidCallback open);

/// App-gated container transform (M3 "container transform") for
/// list-row/card → pushed-detail navigation.
///
/// A thin wrapper over `package:animations`' [OpenContainer] that keeps the
/// app's motion policy and master-detail contract in one place:
///
/// * Duration comes from [Motion.pageTransition] through
///   [AppMotionPolicy.duration]; [OpenContainer] applies its M3 emphasized
///   motion internally. [ContainerTransitionType.fade] is the true
///   size/position morph (`fadeThrough` swaps content without morphing).
/// * The route [OpenContainer] pushes is a normal push on the nearest
///   [Navigator]: back buttons and [Navigator.pop] run the morph in reverse,
///   and the destination is laid out at full navigator size from the first
///   frame (no reflow mid-flight).
/// * Reduce-motion ([AppMotionPolicy.reduceMotion]) and the master-detail
///   gate ([enabled], same contract as `OptionalHero.enabled` — side-pane
///   details have no push to morph into) degrade to [buildAppPageRoute],
///   i.e. exactly the transition every other route resolves to
///   (cross-fade under reduce-motion).
/// * Flat house style: both elevations are pinned to zero so the morph
///   doesn't introduce shadows dense lists don't have.
///
/// Deliberately out of scope (vs raw `OpenContainer`): no `onClosed` result
/// handling, no open-shape/elevation theming, no `useRootNavigator` —
/// callers keep tap handling inside [closedBuilder] (`tappable: false`).
class AppContainerTransform extends StatelessWidget {
  const AppContainerTransform({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.closedColor,
    this.closedBorderRadius,
    this.enabled = true,
  });

  /// The closed card/row. Receives [open] to start the transform.
  final AppContainerTransformClosedBuilder closedBuilder;

  /// Builds the destination page.
  final WidgetBuilder openBuilder;

  /// Background colour the morph starts from. Defaults to the ForUI card
  /// colour; pass the row's actual surface fill when it sits on a tinted
  /// group background so the first frame is seamless.
  final Color? closedColor;

  /// Corner radius the morph starts from; [OpenContainer] lerps it to the
  /// (square) open shape as the window reaches full screen. Defaults to
  /// [BorderRadius.zero].
  final BorderRadius? closedBorderRadius;

  /// Master-detail / wide-surface gate. When `false`, `open` pushes the
  /// destination with the standard app transition instead of morphing.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || AppMotionPolicy.reduceMotion(context)) {
      return Builder(
        builder: (context) =>
            closedBuilder(context, () => _pushFallback(context)),
      );
    }
    final colors = context.theme.colors;
    return OpenContainer<void>(
      // The caller's closedBuilder owns the tap target (`open` is forwarded
      // into the row's own AppTappable), so the wrapper must not add one.
      tappable: false,
      transitionType: ContainerTransitionType.fade,
      transitionDuration: AppMotionPolicy.duration(
        context,
        Motion.pageTransition,
      ),
      closedColor: closedColor ?? colors.card,
      openColor: colors.background,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: closedBorderRadius ?? BorderRadius.zero,
      ),
      closedBuilder: closedBuilder,
      openBuilder: (context, _) => openBuilder(context),
    );
  }

  void _pushFallback(BuildContext context) {
    Navigator.of(context).push<void>(
      buildAppPageRoute<void>(
        context: context,
        pageBuilder: (routeContext, _, _) => openBuilder(routeContext),
      ),
    );
  }
}
