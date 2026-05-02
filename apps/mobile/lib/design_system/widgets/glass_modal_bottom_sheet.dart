import 'package:flutter/material.dart';

import '../tokens/glass_tokens.dart';
import '../tokens/radius_tokens.dart';
import 'glass_surface.dart';

/// Show a modal bottom sheet on a frosted-glass surface.
///
/// Functionally identical to [showModalBottomSheet] — same generic return,
/// same builder contract — except the resulting sheet is wrapped in a
/// [GlassSurface] (sigma 20) and the dim overlay alpha is fixed at 0.5.
///
/// We force the underlying sheet to a transparent background so the only
/// fill is our glass surface; otherwise the Material default fills with
/// `surface` and the blur underneath is invisible.
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
  Color? barrierColor,
  RouteSettings? routeSettings,
}) {
  final tokens = GlassTokens.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
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
    builder: (ctx) => GlassSurface(
      sigma: 20,
      borderRadius: const BorderRadius.only(
        topLeft: Radii.rXl,
        topRight: Radii.rXl,
      ),
      border: Border(
        top: BorderSide(color: tokens.hairlineColor, width: 1),
      ),
      child: builder(ctx),
    ),
  );
}
