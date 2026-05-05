import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../tokens/radius_tokens.dart';

/// Show a modal bottom sheet with iOS 26 Liquid Glass rendering.
///
/// Functionally identical to [showModalBottomSheet] — same generic return,
/// same builder contract — except the resulting sheet is wrapped in a
/// [lgw.GlassContainer] with premium quality for the full shader pipeline.
///
/// Top corners use [Radii.brXl] (20-px) to match the rest of the design
/// system's "tray" tier; bottom corners are square so the sheet still
/// snaps cleanly to the screen edge.
Future<T?> showGlassModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
  Color? barrierColor,
  RouteSettings? routeSettings,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.5),
    backgroundColor: Colors.transparent,
    elevation: 0,
    routeSettings: routeSettings,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radii.rXl,
        topRight: Radii.rXl,
      ),
    ),
    builder: (ctx) => lgw.GlassContainer(
      useOwnLayer: true,
      quality: lgw.GlassQuality.premium,
      shape: const lgw.LiquidRoundedRectangle(borderRadius: 20),
      clipBehavior: Clip.antiAlias,
      child: builder(ctx),
    ),
  );
}
