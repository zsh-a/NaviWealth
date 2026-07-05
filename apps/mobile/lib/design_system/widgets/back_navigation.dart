// Single source of truth for every "go back" path in the app.
//
// Three surfaces ask "what does back mean here?" — the toolbar back
// arrow (smartPop), the Esc shortcut
// (core/shortcuts/global_shortcuts_scope.dart), and the root
// system-back handler (app/app_dock_shell.dart). They all funnel
// through `attemptBack` so the precedence is identical and adding a new
// step (e.g. flushing pending mutations before leaving) is a one-edit
// job here, not three.
//
// Pure path arithmetic (logicalParentOf) and the master-detail
// `?selected=` convention (kSelectedQueryKey / hasSelectedDetail /
// clearSelectedDetail) also live here so the constant and the URI
// rewrite never drift across layers.

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Conventional name for the master-detail "selected row" query
/// parameter — `?selected=<id>`. Owned here so the router, list pages,
/// the back primitives, and the Esc shortcut all reference one string.
const String kSelectedQueryKey = 'selected';

/// Logical parent of [location]: drop the last path segment, ignoring
/// any query string. Primary-tab roots and Home collapse to `/`.
///
///   /activity/expenses/new   -> /activity/expenses
///   /accounts/list/abc123    -> /accounts/list
///   /accounts                -> /   (a primary tab root)
///   /                        -> /
///
/// Public so unit tests can pin the deep-link fallback contract and so
/// `smartPop` can resolve a fallback without duplicating the algorithm.
String logicalParentOf(String location) {
  final path = Uri.parse(location).path;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length <= 1) return '/';
  segments.removeLast();
  return '/${segments.join('/')}';
}

/// `true` when the current router location carries a `?selected=` query
/// — i.e. the desktop master-detail surface has a detail pane open.
///
/// Lets predicates (Esc's [Action.isEnabled], log filters, …) check the
/// master-detail state without rewriting the URI.
bool hasSelectedDetail(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return false;
  return router.routeInformationProvider.value.uri.queryParameters.containsKey(
    kSelectedQueryKey,
  );
}

/// If the current location carries a `?selected=` query, drop just that
/// key (preserving the path and other query keys) and `go()` to the
/// resulting URL. Returns `true` when a clear was performed.
///
/// Used as a "virtual stack entry" on desktop master-detail: clearing
/// `?selected=` unmounts the detail pane without leaving the list page.
bool clearSelectedDetail(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return false;
  final uri = router.routeInformationProvider.value.uri;
  if (!uri.queryParameters.containsKey(kSelectedQueryKey)) return false;
  final next = <String, String>{...uri.queryParameters}
    ..remove(kSelectedQueryKey);
  final rewritten = Uri(
    path: uri.path,
    queryParameters: next.isEmpty ? null : next,
  );
  router.go(rewritten.toString());
  return true;
}

/// Single back primitive shared by [smartPop], the Esc shortcut, and the
/// root system-back handler. Returns `true` when one of the three steps
/// handled the back; `false` when the caller still needs to apply its
/// own fallback (jump-to-Home, exit-arm, deep-link parent, …).
///
/// Precedence — the protocol every surface agrees on:
///
///  1. **`GoRouter.pop()`** — pages reached via `push`/`go` inside a
///     shell branch (the common case: form opened from its list).
///  2. **local `Navigator.pop()`** — modal sheets / dialogs hosting the
///     widget. Skipped at the root navigator because the root's "pop"
///     means "leave the app", which is the caller's decision.
///  3. **clear `?selected=`** — desktop master-detail virtual stack
///     entry.
bool attemptBack(BuildContext context) {
  final goRouter = GoRouter.maybeOf(context);
  if (goRouter != null && goRouter.canPop()) {
    goRouter.pop();
    return true;
  }
  final localNav = Navigator.of(context, rootNavigator: false);
  if (localNav.canPop()) {
    localNav.pop();
    return true;
  }
  if (goRouter != null && clearSelectedDetail(context)) return true;
  return false;
}

/// Toolbar / programmatic "back" used by the header back arrow,
/// post-save handlers, and the route-error page. Calls [attemptBack],
/// then falls back to [fallback] (or the [logicalParentOf] the current
/// location) so deep-linked sub-pages land on their owning list/hub
/// instead of bouncing all the way to Home.
void smartPop(BuildContext context, {String? fallback}) {
  if (attemptBack(context)) return;
  final goRouter = GoRouter.maybeOf(context) ?? GoRouter.of(context);
  final destination =
      fallback ??
      logicalParentOf(goRouter.routeInformationProvider.value.uri.path);
  goRouter.go(destination);
}

/// Form save/delete handlers' one-liner: same as [smartPop] but the
/// fallback is required, expressing the intent "I know where this
/// surface belongs if there is no back stack at all".
void popOrGo(BuildContext context, {required String fallback}) =>
    smartPop(context, fallback: fallback);
