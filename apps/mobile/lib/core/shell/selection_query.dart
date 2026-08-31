import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/widgets/back_navigation.dart';

// `kSelectedQueryKey` is the SoT for the master-detail "selected row"
// query parameter; it lives in design_system so the back primitives and
// the master-detail widget can share it without duplication.
export '../../design_system/widgets/back_navigation.dart'
    show kSelectedQueryKey;

/// Reads `?selected=` off the current router location, or null if absent
/// (or if no GoRouter is mounted — returning null lets shared widgets
/// like `MasterDetailLayout` be used in plain `MaterialApp` tests without
/// stubbing a router).
String? selectedQueryOf(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return null;
  // GoRouterState.of establishes an inherited dependency, so changing only
  // `?selected=` rebuilds the master-detail consumer. Reading the router's
  // routeInformationProvider.value directly would update the URL without
  // necessarily rebuilding the active route widget.
  final raw = GoRouterState.of(context).uri.queryParameters[kSelectedQueryKey];
  if (raw == null || raw.isEmpty) return null;
  return raw;
}

/// Replace the current location's `?selected=` query parameter, preserving
/// the path and any other query keys. Used by master-detail list pages
/// when the user taps a row at desktop width — we never push a new route,
/// because the detail surface is already mounted next to the list.
void replaceSelectedQuery(
  BuildContext context, {
  required String path,
  required String? selected,
}) {
  final current = GoRouterState.of(context).uri;
  final next = <String, String>{...current.queryParameters};
  if (selected == null || selected.isEmpty) {
    next.remove(kSelectedQueryKey);
  } else {
    next[kSelectedQueryKey] = selected;
  }
  final uri = Uri(path: path, queryParameters: next.isEmpty ? null : next);
  GoRouter.of(context).pushReplacement<void>(uri.toString());
}
