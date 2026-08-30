import 'package:flutter/widgets.dart';

import '../tokens/breakpoints.dart';
import '../tokens/dimens_tokens.dart';
import 'adaptive_content_frame.dart';
import 'app_form_scaffold_body.dart';
import 'app_page_scaffold.dart';

typedef AppTaskSliversBuilder = List<Widget> Function(BuildContext context);
typedef AppTaskActionsBuilder = List<Widget> Function(
  BuildContext context,
  bool wide,
);

/// Responsive shell for queue-oriented task pages.
///
/// The primary pane always owns the only scrollable. Compact layouts prepend
/// controls to that same sliver stream; wide layouts move those controls into
/// a fixed 340dp cockpit rail. An optional action footer stays outside the
/// scrollable and aligns with the constrained primary pane.
class AppTaskScaffold extends StatelessWidget {
  const AppTaskScaffold({
    super.key,
    this.title,
    this.titleWidget,
    required this.primarySliversBuilder,
    this.compactLeadingSliversBuilder,
    this.railBuilder,
    this.footerBuilder,
    this.actionsBuilder,
    this.showBack = true,
    this.confirmLeave,
    this.scrollController,
    this.scrollPhysics,
  }) : assert(title != null || titleWidget != null);

  final String? title;
  final Widget? titleWidget;
  final AppTaskSliversBuilder primarySliversBuilder;
  final AppTaskSliversBuilder? compactLeadingSliversBuilder;
  final WidgetBuilder? railBuilder;
  final WidgetBuilder? footerBuilder;
  final AppTaskActionsBuilder? actionsBuilder;
  final bool showBack;
  final Future<bool> Function()? confirmLeave;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Breakpoints.contentTwoColumn;
        final horizontalPadding = Breakpoints.isMobile(constraints.maxWidth)
            ? AppSpacing.s16
            : AppSpacing.s24;
        final maxWidth = wide ? AdaptiveMaxWidth.page : AdaptiveMaxWidth.narrow;
        final hasRail = wide && railBuilder != null;
        final footer = footerBuilder;
        return AppPageScaffold(
          title: title,
          titleWidget: titleWidget,
          actions: actionsBuilder?.call(context, wide) ?? const <Widget>[],
          showBack: showBack,
          confirmLeave: confirmLeave,
          childPad: false,
          child: Column(
            children: [
              Expanded(
                child: AdaptiveContentFrame(
                  maxWidth: maxWidth,
                  layout: hasRail
                      ? AdaptiveFrameLayout.cockpit
                      : AdaptiveFrameLayout.singleColumn,
                  expandSinglePrimary: true,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.s12,
                    horizontalPadding,
                    footer == null
                        ? AppSpacing.s12 + MediaQuery.paddingOf(context).bottom
                        : 0,
                  ),
                  primary: CustomScrollView(
                    key: const Key('app-task-primary-scroll'),
                    controller: scrollController,
                    physics: scrollPhysics,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      if (!wide && compactLeadingSliversBuilder != null)
                        ...compactLeadingSliversBuilder!(context),
                      ...primarySliversBuilder(context),
                    ],
                  ),
                  secondary: hasRail
                      ? KeyedSubtree(
                          key: const Key('app-task-cockpit-rail'),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: railBuilder!(context),
                          ),
                        )
                      : null,
                ),
              ),
              if (footer != null)
                _TaskFooterFrame(
                  hasRail: hasRail,
                  maxWidth: maxWidth,
                  horizontalPadding: horizontalPadding,
                  child: footer(context),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskFooterFrame extends StatelessWidget {
  const _TaskFooterFrame({
    required this.hasRail,
    required this.maxWidth,
    required this.horizontalPadding,
    required this.child,
  });

  final bool hasRail;
  final double maxWidth;
  final double horizontalPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: hasRail
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: AppFormActionBar(child: child)),
                    const SizedBox(width: AppSpacing.s24),
                    const SizedBox(width: kAdaptiveRightRailWidth),
                  ],
                )
              : AppFormActionBar(child: child),
        ),
      ),
    );
  }
}
