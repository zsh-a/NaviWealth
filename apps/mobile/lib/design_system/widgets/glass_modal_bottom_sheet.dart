import 'package:flutter/material.dart';

import '../tokens/radius_tokens.dart';

/// Flat-styled modal bottom sheet (post-glass migration).
///
/// Same call signature as `showModalBottomSheet` so existing call sites
/// (31 of them across the app) continue to compile. The previous
/// implementation wrapped the content in a glass shader; this version
/// renders a plain rounded surface using the active theme.
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
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.5),
    backgroundColor: scheme.surface,
    elevation: 0,
    routeSettings: routeSettings,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radii.rXl,
        topRight: Radii.rXl,
      ),
    ),
    builder: builder,
  );
}
