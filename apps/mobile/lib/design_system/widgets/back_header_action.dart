import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

/// Standard back action for [FHeader.nested.prefixes].
///
/// Pop semantics:
///  1. Closes the topmost route when one exists in the local Navigator
///     (modal sheets, dialogs, anything `Navigator.push`-ed).
///  2. Falls back to GoRouter's `pop()` for routes the shell branched
///     into via `context.push(...)`.
///  3. As a last resort (deep-linked top-level page with no back
///     stack), navigates to the home tab so the user is never trapped.
///
/// Always render as the first entry in `prefixes:` on any pushed page
/// (form pages, detail pages, settings sub-pages). Top-level tab pages
/// must NOT include this — they have nothing to go back to and the
/// bottom navigation already handles tab switching.
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
      if (context.mounted) _smartPop(context);
    },
  );
}

void _smartPop(BuildContext context) {
  final goRouter = GoRouter.maybeOf(context);
  if (goRouter != null && goRouter.canPop()) {
    goRouter.pop();
    return;
  }
  if (Navigator.of(context, rootNavigator: false).canPop()) {
    Navigator.of(context).pop();
    return;
  }
  // Deep-linked into a sub-page with nothing on the stack — drop to the
  // logical parent (the owning list/hub) rather than bouncing the user
  // all the way to the dashboard. Mirrors `logicalParentOf` in
  // `lib/app/nav.dart`; kept local so the design-system layer stays
  // free of app-layer route imports.
  context.go(_logicalParentLocation(context));
}

/// Parent of the current location: drop the last path segment, falling
/// back to Home (`/`) for top-level pages.
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
