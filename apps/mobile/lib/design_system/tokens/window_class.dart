import 'package:flutter/widgets.dart';

import 'breakpoints.dart';

/// High-level width classes for navigation and canonical page layouts.
enum AppWidthClass { compact, medium, expanded, large, extraLarge }

/// Height classes are independent from width so phone landscape and short
/// desktop windows can condense vertical chrome without pretending to be a
/// different device type.
enum AppHeightClass { compact, medium, expanded }

/// Immutable classification of the current application window.
///
/// Use [AppWindowClass.of] only for window-level decisions such as shell
/// navigation. Content widgets should use [LayoutBuilder] and
/// [AppWindowClass.fromSize] with the locally available size.
@immutable
class AppWindowClass {
  const AppWindowClass({required this.width, required this.height});

  factory AppWindowClass.fromSize(Size size) => AppWindowClass(
    width: widthClassFor(size.width),
    height: heightClassFor(size.height),
  );

  factory AppWindowClass.of(BuildContext context) =>
      AppWindowClass.fromSize(MediaQuery.sizeOf(context));

  final AppWidthClass width;
  final AppHeightClass height;

  bool get isCompact => width == AppWidthClass.compact;
  bool get isAtLeastExpanded => width.index >= AppWidthClass.expanded.index;
  bool get isLargeWorkspace => width.index >= AppWidthClass.large.index;
  bool get isExtraLarge => width == AppWidthClass.extraLarge;
  bool get hasCompactHeight => height == AppHeightClass.compact;

  static AppWidthClass widthClassFor(double width) {
    if (width < Breakpoints.mobile) return AppWidthClass.compact;
    if (width < Breakpoints.expanded) return AppWidthClass.medium;
    if (width < Breakpoints.large) return AppWidthClass.expanded;
    if (width < Breakpoints.extraLarge) return AppWidthClass.large;
    return AppWidthClass.extraLarge;
  }

  static AppHeightClass heightClassFor(double height) {
    if (height < Breakpoints.mediumHeight) return AppHeightClass.compact;
    if (height < Breakpoints.expandedHeight) return AppHeightClass.medium;
    return AppHeightClass.expanded;
  }
}
