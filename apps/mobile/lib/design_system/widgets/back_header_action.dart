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
FHeaderAction backHeaderAction(BuildContext context) {
  return FHeaderAction(
    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
    onPress: () => _smartPop(context),
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
  // Deep-linked into a sub-page with nothing on the stack — drop to
  // home so the user has somewhere to go.
  context.go('/');
}
