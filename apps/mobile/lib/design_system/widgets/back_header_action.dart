import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

/// Query-param key the desktop master-detail surface uses to point at the
/// selected row (mirrors `kSelectedQueryKey` in
/// `lib/app/selection_query.dart` — kept private here so the design-system
/// layer doesn't reach into app/).
const String _selectedDetailKey = 'selected';

/// Single back primitive used by [backHeaderAction], `popOrGo`, and the
/// Esc / system-back paths. Precedence:
///
///  1. **`GoRouter.pop()`** — pages reached via `push`/`go` inside a shell
///     branch (the common case: form opened from its list).
///  2. **local `Navigator.pop()`** — modal sheets / dialogs hosting the
///     widget.
///  3. **Clear `?selected=`** — desktop master-detail treats the selected
///     row as a virtual stack entry; clearing it unmounts the detail pane
///     without leaving the list page.
///  4. **`go(fallback)`** — caller-supplied destination, defaulting to
///     the logical parent of the current location (drop the trailing
///     segment, never lower than Home). Used when nothing else can pop —
///     the deep-link case.
///
/// Keeping all four steps in one function means the back arrow, the Esc
/// shortcut, and the post-save `popOrGo` always agree on what "back"
/// means; no caller can accidentally skip the master-detail clear or
/// regress to bouncing the user back to Home.
void smartPop(BuildContext context, {String? fallback}) {
  final goRouter = GoRouter.maybeOf(context);
  if (goRouter != null && goRouter.canPop()) {
    goRouter.pop();
    return;
  }
  if (Navigator.of(context, rootNavigator: false).canPop()) {
    Navigator.of(context).pop();
    return;
  }
  if (goRouter != null && clearSelectedDetail(context)) return;
  final destination = fallback ?? _logicalParentLocation(context);
  (goRouter ?? GoRouter.of(context)).go(destination);
}

/// If the current location carries a `?selected=` query, drop just that
/// key and `go()` to the resulting URL. Returns `true` when a clear was
/// performed.
///
/// Exposed so the Esc shortcut can short-circuit on master-detail without
/// duplicating the URI rewrite.
bool clearSelectedDetail(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return false;
  final uri = router.routeInformationProvider.value.uri;
  if (!uri.queryParameters.containsKey(_selectedDetailKey)) return false;
  final next = <String, String>{...uri.queryParameters}
    ..remove(_selectedDetailKey);
  final rewritten = Uri(
    path: uri.path,
    queryParameters: next.isEmpty ? null : next,
  );
  router.go(rewritten.toString());
  return true;
}

/// Standard back action for [FHeader.nested.prefixes].
///
/// Use this directly only when you also need to add other prefixes
/// alongside the back arrow. For the common case (sub-page = back +
/// optional suffixes), prefer [appSubPageHeader] — it injects this
/// automatically so a forgotten back arrow becomes impossible.
///
/// Top-level tab pages (Today / Activity / Wealth / Plan) MUST NOT use
/// this — they have nothing to go back to and the bottom nav handles
/// tab switching.
///
/// Pass [confirmLeave] on forms that hold unsaved input: it runs before
/// the pop and, when it resolves `false`, the back is cancelled (the
/// user chose to keep editing). See `FormDirtyGuard`.
FHeaderAction backHeaderAction(
  BuildContext context, {
  Future<bool> Function()? confirmLeave,
}) {
  return FHeaderAction(
    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
    onPress: () async {
      if (confirmLeave != null) {
        final mayLeave = await confirmLeave();
        if (!mayLeave) return;
      }
      if (context.mounted) smartPop(context);
    },
  );
}

/// Builds an [FHeader.nested] for a pushed sub-page, with the standard
/// back arrow prepended automatically. The single source of truth for
/// "this page has a back button".
///
/// **Use this on every non-tab page that has a header.** Tab pages
/// (Today / Activity / Wealth / Plan) must use [FHeader.nested]
/// directly so they don't render a back arrow.
///
/// The `tool/check-back-nav-coverage.sh` CI guard enforces this rule:
/// any `FHeader.nested(` outside the tab-page allowlist that also
/// doesn't reference [appSubPageHeader] or [backHeaderAction] fails CI.
///
/// Example:
/// ```dart
/// FScaffold(
///   header: appSubPageHeader(
///     context: context,
///     title: Text(l10n.settingsAppBarTitle),
///     suffixes: [FHeaderAction(icon: ..., onPress: ...)],
///   ),
///   child: ...,
/// )
/// ```
FHeader appSubPageHeader({
  required BuildContext context,
  required Widget title,
  List<Widget> suffixes = const [],
  Future<bool> Function()? confirmLeave,
}) {
  return FHeader.nested(
    title: title,
    prefixes: [backHeaderAction(context, confirmLeave: confirmLeave)],
    suffixes: suffixes,
  );
}

/// Parent of the current location: drop the last path segment, falling
/// back to Home (`/`) for top-level pages. Used as the default `fallback`
/// for [smartPop] so deep-linked sub-pages land on their owning list/hub
/// instead of bouncing all the way to the dashboard.
String _logicalParentLocation(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  final path = router == null
      ? '/'
      : router.routeInformationProvider.value.uri.path;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length <= 1) return '/';
  segments.removeLast();
  return '/${segments.join('/')}';
}
