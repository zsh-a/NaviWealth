import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Pop to the previous route when there is a back stack, otherwise
/// navigate to a logical [fallback].
///
/// Single replacement for the ad-hoc mix of `context.pop()` /
/// `Navigator.of(context).pop()` / `context.go(list)` previously
/// scattered across form save/delete/cancel handlers. Precedence
/// mirrors the long-standing `_smartPop` in
/// `design_system/widgets/back_header_action.dart`:
///
///  1. `GoRouter.pop()` — pages reached via `push`/`go` inside a shell
///     branch (the common case: form opened from its list).
///  2. local `Navigator.pop()` — modal sheets / dialogs hosting the
///     widget.
///  3. `go(fallback)` — the deep-link case with no back stack at all.
///     [fallback] must be a real destination (the owning list / hub),
///     never a bare `/` unless that genuinely is the parent.
void popOrGo(BuildContext context, {required String fallback}) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    router.pop();
    return;
  }
  final navigator = Navigator.of(context, rootNavigator: false);
  if (navigator.canPop()) {
    navigator.pop();
    return;
  }
  (router ?? GoRouter.of(context)).go(fallback);
}

/// Logical parent of [location]: drop the last path segment.
///
/// Used as the deep-link `popOrGo` fallback so "back" lands on the
/// parent list/hub instead of bouncing the user to the dashboard.
///
///   /activity/expenses/new   -> /activity/expenses
///   /accounts/list/abc123    -> /accounts/list
///   /accounts                -> /   (a primary tab root)
///   /                        -> /
String logicalParentOf(String location) {
  final path = Uri.parse(location).path;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length <= 1) return '/';
  segments.removeLast();
  return '/${segments.join('/')}';
}
