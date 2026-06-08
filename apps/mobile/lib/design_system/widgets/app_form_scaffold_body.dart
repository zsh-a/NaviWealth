import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Full-screen form body with a scrollable field area and a pinned action bar.
///
/// Use inside a page-level
/// `FScaffold(childPad: false, resizeToAvoidBottomInset: false, child: ...)`.
///
/// This widget owns keyboard avoidance so every form keeps the same geometry:
/// the fields stay scrollable and the primary action bar moves as one block
/// above the IME instead of letting nested scaffolds/resize modes double-count
/// the keyboard inset on some Android keyboards.
class AppFormScaffoldBody extends StatelessWidget {
  const AppFormScaffoldBody({
    super.key,
    required this.children,
    required this.action,
    this.padding = const EdgeInsets.all(AppSpacing.s16),
    this.controller,
    this.physics,
  });

  final List<Widget> children;
  final Widget action;
  final EdgeInsets padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: Motion.ambient,
      curve: Motion.standardDecelerate,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              physics: physics,
              padding: padding,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
          AppFormActionBar(child: action),
        ],
      ),
    );
  }
}

/// Pinned action bar with frosted glass effect — matches the sheet and
/// nav bar aesthetic for a unified glass-morphism language.
class AppFormActionBar extends StatelessWidget {
  const AppFormActionBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.s16,
      AppSpacing.s16,
      AppSpacing.s16,
      AppSpacing.s12,
    ),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final surface = colors.background.withValues(
      alpha: isDark ? AppOpacity.nearOpaqueDark : AppOpacity.nearOpaque,
    );
    final hairline = colors.foreground.withValues(
      alpha: isDark ? AppOpacity.light : AppOpacity.subtle,
    );
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: AppBlur.sheet,
          sigmaY: AppBlur.sheet,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            border: Border(top: BorderSide(color: hairline)),
          ),
          child: SafeArea(top: false, minimum: padding, child: child),
        ),
      ),
    );
  }
}
