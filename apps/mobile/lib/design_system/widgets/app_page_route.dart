import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// Imperative details share declarative navigation, including iOS back gestures.
PageRoute<T> buildAppPageRoute<T>({
  required BuildContext context,
  required RoutePageBuilder pageBuilder,
  bool fullscreenDialog = false,
}) {
  final native = Theme.of(context).platform == TargetPlatform.iOS;
  final enter = native
      ? const CupertinoPageTransitionsBuilder().transitionDuration
      : Motion.pageTransition;
  final leave = native ? enter : Motion.pageReturn;
  return _AppPageRoute<T>(
    enter: AppMotionPolicy.duration(context, enter),
    leave: AppMotionPolicy.duration(context, leave),
    fullscreenDialog: fullscreenDialog,
    builder: (context) {
      final route = ModalRoute.of(context)!;
      return pageBuilder(context, route.animation!, route.secondaryAnimation!);
    },
  );
}

class _AppPageRoute<T> extends MaterialPageRoute<T> {
  _AppPageRoute({
    required this.enter,
    required this.leave,
    required super.builder,
    required super.fullscreenDialog,
  });

  final Duration enter;
  final Duration leave;

  @override
  Duration get transitionDuration => enter;

  @override
  Duration get reverseTransitionDuration => leave;
}
