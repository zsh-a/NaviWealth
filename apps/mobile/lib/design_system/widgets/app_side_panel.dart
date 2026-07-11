import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/semantic_colors.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Presents a desktop inspector from the trailing edge of the viewport.
///
/// Business features provide only their body. Scrim, motion, surface, border,
/// shadow and safe-area behavior stay uniform across every inspector.
Future<T?> showAppSidePanel<T>({
  required BuildContext context,
  required String barrierLabel,
  required WidgetBuilder builder,
  double width = 430,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierLabel: barrierLabel,
    barrierDismissible: barrierDismissible,
    barrierColor: SemanticColors.of(context).scrim,
    transitionDuration: AppMotionPolicy.duration(
      context,
      Motion.medium,
      role: AppMotionRole.transition,
    ),
    pageBuilder: (panelContext, _, _) => _AppSidePanel(
      width: width,
      child: Builder(builder: builder),
    ),
    transitionBuilder: (context, animation, _, child) {
      final direction = Directionality.of(context) == TextDirection.rtl
          ? -1.0
          : 1.0;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.standardDecelerate,
        reverseCurve: Motion.standardAccelerate,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: Offset(direction, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _AppSidePanel extends StatelessWidget {
  const _AppSidePanel({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SafeArea(
        left: false,
        right: false,
        child: Container(
          width: width,
          height: double.infinity,
          decoration: BoxDecoration(
            color: colors.background,
            border: BorderDirectional(
              start: BorderSide(
                color: colors.border,
                width: AppStroke.hairline,
              ),
            ),
            boxShadow: AppShadow.panel,
          ),
          child: child,
        ),
      ),
    );
  }
}
