import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/component_specs.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'adaptive_content_frame.dart';
import 'app_glass.dart';

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
    this.onSubmit,
    this.maxContentWidth = AdaptiveMaxWidth.narrow,
  });

  final List<Widget> children;
  final Widget action;
  final EdgeInsets padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final double maxContentWidth;

  /// Enables the standard keyboard form-submit shortcuts. Keep this null when
  /// the primary action is disabled so modified Enter keeps propagating.
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        final constrainWideContent =
            constraints.maxWidth > maxContentWidth + padding.horizontal;
        Widget formContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
        if (constrainWideContent) {
          formContent = Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: formContent,
            ),
          );
        }

        final body = FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: AnimatedPadding(
            duration: AppMotionPolicy.duration(context, Motion.ambient),
            curve: Motion.standardDecelerate,
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: controller,
                    physics: physics,
                    padding: padding,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: formContent,
                  ),
                ),
                AppFormActionBar(
                  maxContentWidth: constrainWideContent
                      ? maxContentWidth
                      : null,
                  child: action,
                ),
              ],
            ),
          ),
        );

        final submit = onSubmit;
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          descendantsAreFocusable: true,
          child: CallbackShortcuts(
            bindings: submit == null
                ? const <ShortcutActivator, VoidCallback>{}
                : <ShortcutActivator, VoidCallback>{
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      meta: true,
                      includeRepeats: false,
                    ): submit,
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                      includeRepeats: false,
                    ): submit,
                    const SingleActivator(
                      LogicalKeyboardKey.numpadEnter,
                      meta: true,
                      includeRepeats: false,
                    ): submit,
                    const SingleActivator(
                      LogicalKeyboardKey.numpadEnter,
                      control: true,
                      includeRepeats: false,
                    ): submit,
                  },
            child: body,
          ),
        );
      },
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
    this.maxContentWidth,
  });

  final Widget child;
  final EdgeInsets padding;
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final contentWidth = maxContentWidth;
    final content = contentWidth == null
        ? child
        : Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: contentWidth, child: child),
          );
    return AppGlassSurface(
      role: AppGlassRole.sheet,
      child: SafeArea(top: false, minimum: padding, child: content),
    );
  }
}
