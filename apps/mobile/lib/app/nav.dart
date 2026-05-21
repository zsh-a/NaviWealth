import 'package:flutter/widgets.dart';

import '../design_system/design_system.dart';

/// Pop to the previous route when there is a back stack, otherwise
/// navigate to a logical [fallback].
///
/// Thin wrapper over [smartPop] (`design_system/widgets/back_header_action.dart`)
/// that forwards an explicit fallback — i.e. "where this surface logically
/// belongs when there is no back stack at all" (typically the owning list
/// or hub). All four precedence steps live in `smartPop`; keeping this
/// wrapper means form save/delete handlers can read in one line as
/// `popOrGo(context, fallback: AppRoutes.accountsList)`.
void popOrGo(BuildContext context, {required String fallback}) =>
    smartPop(context, fallback: fallback);

/// Logical parent of [location]: drop the last path segment.
///
/// Public so unit tests can pin the deep-link fallback contract.
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
