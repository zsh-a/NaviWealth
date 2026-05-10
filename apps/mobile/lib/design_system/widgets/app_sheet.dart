import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/motion_tokens.dart';

/// Unified bottom-sheet shell — every modal sheet in the app should
/// reach the screen through [showAppSheet] so the drag handle, title
/// row, surface tint, padding and dismiss affordance look identical.
///
/// Drop-in replacement for `showFSheet`; the [builder] receives a
/// `BuildContext` for the sheet body. Pass [title] / [actions] for the
/// header row, [scrollable] when the body is a list (default true so
/// long sheets won't blow out on small phones).
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  List<Widget> actions = const [],
  bool scrollable = true,
  double? maxHeightFactor,
}) {
  return showFSheet<T>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: maxHeightFactor,
    builder: (sheetContext) => AppSheet(
      title: title,
      actions: actions,
      scrollable: scrollable,
      child: Builder(builder: builder),
    ),
  );
}

/// Internal shell — wraps the body with the unified chrome. Public
/// only so existing call sites that already wired their own
/// `showFSheet` can migrate without changing their open mechanism.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.scrollable = true,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final body = scrollable
        ? SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: child,
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: child,
          );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle — small, muted, centered.
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: colors.mutedForeground.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title row — leading title + trailing actions; matches the
          // weight of an inline page header so the user knows they're
          // still in the same product surface.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: context.theme.typography.lg.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          AnimatedSize(
            duration: Motion.fast,
            curve: Motion.standardDecelerate,
            alignment: Alignment.topCenter,
            child: body,
          ),
        ],
      ),
    );
  }
}
