import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/selection_query.dart';
import '../../../design_system/widgets/form_leave_scope.dart';

/// onExit does not run when a route's path parameters or query change. Check
/// the still-mounted route before a replacement can dispose its editor.
Future<String?> guardKnowledgeDetailChange(
  BuildContext context,
  GoRouterState next,
) async {
  final router = GoRouter.of(context);
  if (router.routerDelegate.currentConfiguration.isEmpty) return null;
  final current = router.routerDelegate.state.uri;
  if (current.path == next.uri.path &&
      current.queryParameters[kSelectedQueryKey] ==
          next.uri.queryParameters[kSelectedQueryKey]) {
    return null;
  }
  final guard = FormLeaveScope.forRouter(router, path: current.path);
  if (guard == null || !guard.hasPendingChanges) return null;
  return await guard.confirmLeave() ? null : current.toString();
}
