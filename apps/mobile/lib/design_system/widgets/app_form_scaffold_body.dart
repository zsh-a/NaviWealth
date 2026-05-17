import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';

/// Full-screen form body with a scrollable field area and a pinned action bar.
///
/// Use inside a page-level `FScaffold(childPad: false, child: ...)`.
/// `FScaffold` owns keyboard avoidance; this widget keeps the primary action
/// out of the scroll extent so focusing the last input does not push it to the
/// top of the available viewport.
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
    return Column(
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
    );
  }
}

class AppFormActionBar extends StatelessWidget {
  const AppFormActionBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.s16,
      AppSpacing.s12,
      AppSpacing.s16,
      AppSpacing.s12,
    ),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final hairline = colors.foreground.withValues(
      alpha: colors.brightness == Brightness.dark ? 0.12 : 0.10,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: hairline)),
      ),
      child: SafeArea(top: false, minimum: padding, child: child),
    );
  }
}
