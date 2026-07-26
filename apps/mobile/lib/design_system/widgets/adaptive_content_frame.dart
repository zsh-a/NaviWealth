import 'package:flutter/material.dart';

import '../tokens/breakpoints.dart';
import '../tokens/dimens_tokens.dart';

const double kAdaptiveRightRailWidth = 340;

/// Standard page-level frame for responsive content surfaces.
///
/// The app shell decides navigation shape. This frame decides how ordinary
/// page content uses the remaining viewport: padding, maximum readable width,
/// column strategy, section spacing, and optional desktop right rail.
class AdaptiveContentFrame extends StatelessWidget {
  const AdaptiveContentFrame({
    super.key,
    required this.primary,
    this.secondary,
    this.header,
    this.maxWidth = AdaptiveMaxWidth.page,
    this.layout = AdaptiveFrameLayout.singleColumn,
    this.padding,
    this.sectionGap = AppSpacing.s20,
    this.columnGap = AppSpacing.s24,
    this.columnBreakpoint = Breakpoints.contentTwoColumn,
    this.rightRailWidth = kAdaptiveRightRailWidth,
    this.primaryFlex = 1,
    this.secondaryFlex = 1,
    this.alignment = Alignment.topCenter,
    this.expandSinglePrimary = false,
  });

  final Widget primary;
  final Widget? secondary;
  final Widget? header;
  final double maxWidth;
  final AdaptiveFrameLayout layout;
  final EdgeInsetsGeometry? padding;
  final double sectionGap;
  final double columnGap;
  final double columnBreakpoint;
  final double rightRailWidth;
  final int primaryFlex;
  final int secondaryFlex;
  final AlignmentGeometry alignment;
  final bool expandSinglePrimary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final content = _FrameContent(
          header: header,
          primary: primary,
          secondary: secondary,
          layout: layout,
          sectionGap: sectionGap,
          columnGap: columnGap,
          rightRailWidth: rightRailWidth,
          primaryFlex: primaryFlex,
          secondaryFlex: secondaryFlex,
          useColumns: _shouldUseColumns(width),
          expandBody: constraints.hasBoundedHeight,
          expandSinglePrimary: expandSinglePrimary,
        );
        return Padding(
          padding: padding ?? _defaultPadding(context, width),
          child: Align(
            alignment: alignment,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: content,
            ),
          ),
        );
      },
    );
  }

  bool _shouldUseColumns(double width) {
    return secondary != null &&
        layout != AdaptiveFrameLayout.singleColumn &&
        width >= columnBreakpoint;
  }

  EdgeInsets _defaultPadding(BuildContext context, double width) {
    final base = Breakpoints.isMobile(width)
        ? const EdgeInsets.all(AppSpacing.s16)
        : const EdgeInsets.all(AppSpacing.s24);
    return base.copyWith(
      bottom: base.bottom + MediaQuery.paddingOf(context).bottom,
    );
  }
}

class _FrameContent extends StatelessWidget {
  const _FrameContent({
    required this.header,
    required this.primary,
    required this.secondary,
    required this.layout,
    required this.sectionGap,
    required this.columnGap,
    required this.rightRailWidth,
    required this.primaryFlex,
    required this.secondaryFlex,
    required this.useColumns,
    required this.expandBody,
    required this.expandSinglePrimary,
  });

  final Widget? header;
  final Widget primary;
  final Widget? secondary;
  final AdaptiveFrameLayout layout;
  final double sectionGap;
  final double columnGap;
  final double rightRailWidth;
  final int primaryFlex;
  final int secondaryFlex;
  final bool useColumns;
  final bool expandBody;
  final bool expandSinglePrimary;

  @override
  Widget build(BuildContext context) {
    final body = _body();
    final hasHeader = header != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasHeader) header!,
        if (hasHeader) SizedBox(height: sectionGap),
        if (expandBody) Expanded(child: body) else body,
      ],
    );
  }

  Widget _body() {
    final secondary = this.secondary;
    if (!useColumns || secondary == null) {
      if (secondary == null && expandSinglePrimary) return primary;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          if (secondary != null) ...[SizedBox(height: sectionGap), secondary],
        ],
      );
    }

    if (layout == AdaptiveFrameLayout.cockpit) {
      return Row(
        crossAxisAlignment: expandBody
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.start,
        children: [
          Expanded(child: primary),
          SizedBox(width: columnGap),
          SizedBox(width: rightRailWidth, child: secondary),
        ],
      );
    }

    return Row(
      crossAxisAlignment: expandBody
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        Expanded(flex: primaryFlex, child: primary),
        SizedBox(width: columnGap),
        Expanded(flex: secondaryFlex, child: secondary),
      ],
    );
  }
}

enum AdaptiveFrameLayout { singleColumn, twoColumn, cockpit }

class AdaptiveMaxWidth {
  const AdaptiveMaxWidth._();

  /// Focused reading and form measure. 640 keeps labels, inputs, and helper
  /// copy within a comfortable scan width on desktop instead of stretching a
  /// mobile form across most of the window.
  static const double narrow = 640;
  static const double page = 1200;
  static const double dashboard = 1440;
}
